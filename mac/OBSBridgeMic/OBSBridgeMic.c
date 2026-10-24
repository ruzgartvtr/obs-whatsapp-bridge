/*
 * OBS Bridge Mic — minimal macOS Audio Server Plugin (loopback).
 * OBS monitors audio into the output side; WhatsApp (and others) capture the input side.
 *
 * Build on macOS, then:
 *   sudo cp -R OBSBridgeMic.driver /Library/Audio/Plug-Ins/HAL/
 *   sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
 */

#include "OBSBridgeMic.h"

#include <mach/mach_time.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

OBSBridgeState g_state;

#pragma mark - Ring buffer

void OBSBridge_RingInit(void)
{
	size_t n = (size_t)OBS_BRIDGE_RING_FRAMES * OBS_BRIDGE_CHANNELS;
	g_state.ring = (Float32 *)calloc(n, sizeof(Float32));
	atomic_store(&g_state.write_pos, 0);
	atomic_store(&g_state.read_pos, 0);
}

void OBSBridge_RingTeardown(void)
{
	free(g_state.ring);
	g_state.ring = NULL;
}

void OBSBridge_RingWrite(const Float32 *src, UInt32 frames)
{
	if (!g_state.ring || !src || frames == 0)
		return;
	UInt64 w = atomic_load(&g_state.write_pos);
	for (UInt32 i = 0; i < frames; ++i) {
		UInt32 idx = (UInt32)((w + i) % OBS_BRIDGE_RING_FRAMES);
		g_state.ring[idx * 2 + 0] = src[i * 2 + 0] * g_state.volume;
		g_state.ring[idx * 2 + 1] = src[i * 2 + 1] * g_state.volume;
	}
	atomic_store(&g_state.write_pos, w + frames);
	/* Keep read cursor from falling more than one buffer behind. */
	UInt64 r = atomic_load(&g_state.read_pos);
	if (w + frames > r + OBS_BRIDGE_RING_FRAMES)
		atomic_store(&g_state.read_pos, w + frames - OBS_BRIDGE_RING_FRAMES);
}

void OBSBridge_RingRead(Float32 *dst, UInt32 frames)
{
	if (!dst || frames == 0)
		return;
	if (!g_state.ring) {
		memset(dst, 0, frames * OBS_BRIDGE_CHANNELS * sizeof(Float32));
		return;
	}
	UInt64 r = atomic_load(&g_state.read_pos);
	UInt64 w = atomic_load(&g_state.write_pos);
	for (UInt32 i = 0; i < frames; ++i) {
		if (r + i >= w) {
			dst[i * 2 + 0] = 0;
			dst[i * 2 + 1] = 0;
		} else {
			UInt32 idx = (UInt32)((r + i) % OBS_BRIDGE_RING_FRAMES);
			dst[i * 2 + 0] = g_state.ring[idx * 2 + 0];
			dst[i * 2 + 1] = g_state.ring[idx * 2 + 1];
		}
	}
	atomic_store(&g_state.read_pos, r + frames);
}

#pragma mark - Helpers

static Boolean OB_HasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID,
			      pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress);
static OSStatus OB_IsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID,
				      pid_t inClientProcessID,
				      const AudioObjectPropertyAddress *inAddress,
				      Boolean *outIsSettable);
static OSStatus OB_GetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID,
				       pid_t inClientProcessID,
				       const AudioObjectPropertyAddress *inAddress,
				       UInt32 inQualifierDataSize, const void *inQualifierData,
				       UInt32 *outDataSize);
static OSStatus OB_GetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID,
				   pid_t inClientProcessID,
				   const AudioObjectPropertyAddress *inAddress,
				   UInt32 inQualifierDataSize, const void *inQualifierData,
				   UInt32 inDataSize, UInt32 *outDataSize, void *outData);
static OSStatus OB_SetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID,
				   pid_t inClientProcessID,
				   const AudioObjectPropertyAddress *inAddress,
				   UInt32 inQualifierDataSize, const void *inQualifierData,
				   UInt32 inDataSize, const void *inData);
static OSStatus OB_StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID,
			   UInt32 inClientID);
static OSStatus OB_StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID,
			  UInt32 inClientID);
static OSStatus OB_GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver,
				    AudioObjectID inDeviceObjectID, UInt32 inClientID,
				    Float64 *outSampleTime, UInt64 *outHostTime,
				    UInt64 *outSeed);
static OSStatus OB_WillDoIOOperation(AudioServerPlugInDriverRef inDriver,
				     AudioObjectID inDeviceObjectID, UInt32 inClientID,
				     UInt32 inOperationID, Boolean *outWillDo,
				     Boolean *outWillDoInPlace);
static OSStatus OB_BeginIOOperation(AudioServerPlugInDriverRef inDriver,
				    AudioObjectID inDeviceObjectID, UInt32 inClientID,
				    UInt32 inOperationID, UInt32 inIOBufferFrameSize,
				    const AudioServerPlugInIOCycleInfo *inIOCycleInfo);
static OSStatus OB_DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID,
				 AudioObjectID inStreamObjectID, UInt32 inClientID,
				 UInt32 inOperationID, UInt32 inIOBufferFrameSize,
				 const AudioServerPlugInIOCycleInfo *inIOCycleInfo,
				 void *ioMainBuffer, void *ioSecondaryBuffer);
static OSStatus OB_EndIOOperation(AudioServerPlugInDriverRef inDriver,
				  AudioObjectID inDeviceObjectID, UInt32 inClientID,
				  UInt32 inOperationID, UInt32 inIOBufferFrameSize,
				  const AudioServerPlugInIOCycleInfo *inIOCycleInfo);

static AudioServerPlugInDriverInterface g_interface = {
	NULL,
	NULL, /* QueryInterface filled at factory */
	NULL,
	NULL,
	OB_HasProperty,
	OB_IsPropertySettable,
	OB_GetPropertyDataSize,
	OB_GetPropertyData,
	OB_SetPropertyData,
	NULL, /* Device_Initialize */
	NULL, /* Device_Teardown */
	OB_StartIO,
	OB_StopIO,
	NULL, /* Device_PerformConfigChange */
	NULL, /* Device_AbortConfigChange */
	NULL, /* Device_RequestConfigChange */
	OB_GetZeroTimeStamp,
	OB_WillDoIOOperation,
	OB_BeginIOOperation,
	OB_DoIOOperation,
	OB_EndIOOperation,
};

static AudioServerPlugInDriverInterface *g_interface_ptr = &g_interface;
static AudioServerPlugInDriverRef g_driver_ref = &g_interface_ptr;

static CFStringRef CFSTR_DEVICE_NAME = CFSTR("OBS Bridge Mic");
static CFStringRef CFSTR_DEVICE_UID = CFSTR("OBSBridgeMic_UID");
static CFStringRef CFSTR_DEVICE_MODEL = CFSTR("OBSBridgeMic_Model");
static CFStringRef CFSTR_BOX_UID = CFSTR("OBSBridgeMic_Box_UID");
static CFStringRef CFSTR_INPUT_NAME = CFSTR("OBS Bridge Mic Input");
static CFStringRef CFSTR_OUTPUT_NAME = CFSTR("OBS Bridge Mic Output");

#pragma mark - COM-ish factory

static HRESULT OB_QueryInterface(void *inDriver, REFIID inUUID, LPVOID *outInterface)
{
	(void)inDriver;
	if (!outInterface)
		return E_POINTER;
	*outInterface = NULL;
	if (CFEqual(inUUID, CFUUIDGetConstantUUIDWithBytes(
				    NULL, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0,
				    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46)) ||
	    CFEqual(inUUID, kAudioServerPlugInDriverInterfaceUUID)) {
		*outInterface = g_driver_ref;
		return S_OK;
	}
	return E_NOINTERFACE;
}

static ULONG OB_AddRef(void *inDriver)
{
	(void)inDriver;
	return 1;
}

static ULONG OB_Release(void *inDriver)
{
	(void)inDriver;
	return 1;
}

__attribute__((visibility("default"))) void *OBSBridgeMicFactory(CFAllocatorRef allocator,
								  CFUUIDRef typeUUID)
{
	(void)allocator;
	if (!CFEqual(typeUUID, kAudioServerPlugInTypeUUID))
		return NULL;

	g_interface._reserved = NULL;
	g_interface.QueryInterface = OB_QueryInterface;
	g_interface.AddRef = OB_AddRef;
	g_interface.Release = OB_Release;

	memset(&g_state, 0, sizeof(g_state));
	g_state.volume = 1.0f;
	OBSBridge_RingInit();
	return g_driver_ref;
}

#pragma mark - Property dispatch (minimal)

static Boolean OB_HasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID,
			      pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress)
{
	(void)inDriver;
	(void)inClientProcessID;
	if (!inAddress)
		return false;

	switch (inObjectID) {
	case kObjectID_PlugIn:
		switch (inAddress->mSelector) {
		case kAudioObjectPropertyBaseClass:
		case kAudioObjectPropertyClass:
		case kAudioObjectPropertyOwner:
		case kAudioObjectPropertyManufacturer:
		case kAudioObjectPropertyOwnedObjects:
		case kAudioPlugInPropertyBoxList:
		case kAudioPlugInPropertyTranslateUIDToBox:
		case kAudioPlugInPropertyDeviceList:
		case kAudioPlugInPropertyTranslateUIDToDevice:
		case kAudioObjectPropertyCustomPropertyInfoList:
			return true;
		default:
			return false;
		}
	case kObjectID_Box:
		switch (inAddress->mSelector) {
		case kAudioObjectPropertyBaseClass:
		case kAudioObjectPropertyClass:
		case kAudioObjectPropertyOwner:
		case kAudioObjectPropertyName:
		case kAudioObjectPropertyModelName:
		case kAudioObjectPropertyManufacturer:
		case kAudioObjectPropertyOwnedObjects:
		case kAudioBoxPropertyBoxUID:
		case kAudioBoxPropertyTransportType:
		case kAudioBoxPropertyHasAudio:
		case kAudioBoxPropertyHasVideo:
		case kAudioBoxPropertyHasMIDI:
		case kAudioBoxPropertyIsProtected:
		case kAudioBoxPropertyAcquired:
		case kAudioBoxPropertyAcquisitionFailed:
		case kAudioBoxPropertyDeviceList:
			return true;
		default:
			return false;
		}
	case kObjectID_Device:
		switch (inAddress->mSelector) {
		case kAudioObjectPropertyBaseClass:
		case kAudioObjectPropertyClass:
		case kAudioObjectPropertyOwner:
		case kAudioObjectPropertyName:
		case kAudioObjectPropertyManufacturer:
		case kAudioObjectPropertyOwnedObjects:
		case kAudioDevicePropertyDeviceUID:
		case kAudioDevicePropertyModelUID:
		case kAudioDevicePropertyTransportType:
		case kAudioDevicePropertyRelatedDevices:
		case kAudioDevicePropertyClockDomain:
		case kAudioDevicePropertyDeviceIsAlive:
		case kAudioDevicePropertyDeviceIsRunning:
		case kAudioDevicePropertyDeviceCanBeDefaultDevice:
		case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
		case kAudioDevicePropertyLatency:
		case kAudioDevicePropertyStreams:
		case kAudioObjectPropertyControlList:
		case kAudioDevicePropertyNominalSampleRate:
		case kAudioDevicePropertyAvailableNominalSampleRates:
		case kAudioDevicePropertyIsHidden:
		case kAudioDevicePropertyPreferredChannelsForStereo:
		case kAudioDevicePropertyPreferredChannelLayout:
			return true;
		default:
			return false;
		}
	case kObjectID_Stream_Input:
	case kObjectID_Stream_Output:
		switch (inAddress->mSelector) {
		case kAudioObjectPropertyBaseClass:
		case kAudioObjectPropertyClass:
		case kAudioObjectPropertyOwner:
		case kAudioObjectPropertyName:
		case kAudioStreamPropertyIsActive:
		case kAudioStreamPropertyDirection:
		case kAudioStreamPropertyTerminalType:
		case kAudioStreamPropertyStartingChannel:
		case kAudioStreamPropertyLatency:
		case kAudioStreamPropertyVirtualFormat:
		case kAudioStreamPropertyPhysicalFormat:
		case kAudioStreamPropertyAvailableVirtualFormats:
		case kAudioStreamPropertyAvailablePhysicalFormats:
			return true;
		default:
			return false;
		}
	default:
		return false;
	}
}

static OSStatus OB_IsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID,
				      pid_t inClientProcessID,
				      const AudioObjectPropertyAddress *inAddress,
				      Boolean *outIsSettable)
{
	(void)inDriver;
	(void)inObjectID;
	(void)inClientProcessID;
	(void)inAddress;
	if (!outIsSettable)
		return kAudioHardwareIllegalOperationError;
	*outIsSettable = false;
	return kAudioHardwareNoError;
}

static AudioStreamBasicDescription stereo_asbd(void)
{
	AudioStreamBasicDescription asbd = {0};
	asbd.mSampleRate = OBS_BRIDGE_SAMPLE_RATE;
	asbd.mFormatID = kAudioFormatLinearPCM;
	asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked |
			    kAudioFormatFlagIsNonInterleaved;
	/* Use interleaved float for simpler ring IO; declare as interleaved. */
	asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
	asbd.mBytesPerPacket = 8;
	asbd.mFramesPerPacket = 1;
	asbd.mBytesPerFrame = 8;
	asbd.mChannelsPerFrame = 2;
	asbd.mBitsPerChannel = 32;
	return asbd;
}

static OSStatus OB_GetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID,
				       pid_t inClientProcessID,
				       const AudioObjectPropertyAddress *inAddress,
				       UInt32 inQualifierDataSize, const void *inQualifierData,
				       UInt32 *outDataSize)
{
	(void)inDriver;
	(void)inClientProcessID;
	(void)inQualifierDataSize;
	(void)inQualifierData;
	if (!inAddress || !outDataSize)
		return kAudioHardwareIllegalOperationError;

	switch (inAddress->mSelector) {
	case kAudioObjectPropertyBaseClass:
	case kAudioObjectPropertyClass:
	case kAudioObjectPropertyOwner:
	case kAudioDevicePropertyTransportType:
	case kAudioDevicePropertyClockDomain:
	case kAudioDevicePropertyLatency:
	case kAudioStreamPropertyDirection:
	case kAudioStreamPropertyTerminalType:
	case kAudioStreamPropertyStartingChannel:
	case kAudioStreamPropertyLatency:
	case kAudioBoxPropertyTransportType:
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioObjectPropertyManufacturer:
	case kAudioObjectPropertyName:
	case kAudioObjectPropertyModelName:
	case kAudioDevicePropertyDeviceUID:
	case kAudioDevicePropertyModelUID:
	case kAudioBoxPropertyBoxUID:
		*outDataSize = sizeof(CFStringRef);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyDeviceIsAlive:
	case kAudioDevicePropertyDeviceIsRunning:
	case kAudioDevicePropertyDeviceCanBeDefaultDevice:
	case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
	case kAudioDevicePropertyIsHidden:
	case kAudioStreamPropertyIsActive:
	case kAudioBoxPropertyHasAudio:
	case kAudioBoxPropertyHasVideo:
	case kAudioBoxPropertyHasMIDI:
	case kAudioBoxPropertyIsProtected:
	case kAudioBoxPropertyAcquired:
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyNominalSampleRate:
		*outDataSize = sizeof(Float64);
		return kAudioHardwareNoError;
	case kAudioObjectPropertyOwnedObjects:
		if (inObjectID == kObjectID_PlugIn)
			*outDataSize = sizeof(AudioObjectID); /* box */
		else if (inObjectID == kObjectID_Box)
			*outDataSize = sizeof(AudioObjectID); /* device */
		else if (inObjectID == kObjectID_Device)
			*outDataSize = sizeof(AudioObjectID) * 2; /* streams */
		else
			*outDataSize = 0;
		return kAudioHardwareNoError;
	case kAudioPlugInPropertyBoxList:
	case kAudioBoxPropertyDeviceList:
		*outDataSize = sizeof(AudioObjectID);
		return kAudioHardwareNoError;
	case kAudioPlugInPropertyDeviceList:
		*outDataSize = sizeof(AudioObjectID);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyStreams:
		if (inAddress->mScope == kAudioObjectPropertyScopeGlobal)
			*outDataSize = sizeof(AudioObjectID) * 2;
		else
			*outDataSize = sizeof(AudioObjectID);
		return kAudioHardwareNoError;
	case kAudioObjectPropertyControlList:
		*outDataSize = 0;
		return kAudioHardwareNoError;
	case kAudioDevicePropertyRelatedDevices:
		*outDataSize = sizeof(AudioObjectID);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyAvailableNominalSampleRates:
		*outDataSize = sizeof(AudioValueRange);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyPreferredChannelsForStereo:
		*outDataSize = sizeof(UInt32) * 2;
		return kAudioHardwareNoError;
	case kAudioDevicePropertyPreferredChannelLayout: {
		*outDataSize = offsetof(AudioChannelLayout, mChannelDescriptions) +
			       sizeof(AudioChannelDescription) * 2;
		return kAudioHardwareNoError;
	}
	case kAudioStreamPropertyVirtualFormat:
	case kAudioStreamPropertyPhysicalFormat:
		*outDataSize = sizeof(AudioStreamBasicDescription);
		return kAudioHardwareNoError;
	case kAudioStreamPropertyAvailableVirtualFormats:
	case kAudioStreamPropertyAvailablePhysicalFormats:
		*outDataSize = sizeof(AudioStreamRangedDescription);
		return kAudioHardwareNoError;
	case kAudioPlugInPropertyTranslateUIDToBox:
	case kAudioPlugInPropertyTranslateUIDToDevice:
		*outDataSize = sizeof(AudioObjectID);
		return kAudioHardwareNoError;
	case kAudioBoxPropertyAcquisitionFailed:
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioObjectPropertyCustomPropertyInfoList:
		*outDataSize = 0;
		return kAudioHardwareNoError;
	default:
		return kAudioHardwareUnknownPropertyError;
	}
}

static OSStatus OB_GetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID,
				   pid_t inClientProcessID,
				   const AudioObjectPropertyAddress *inAddress,
				   UInt32 inQualifierDataSize, const void *inQualifierData,
				   UInt32 inDataSize, UInt32 *outDataSize, void *outData)
{
	(void)inDriver;
	(void)inClientProcessID;
	if (!inAddress || !outDataSize || !outData)
		return kAudioHardwareIllegalOperationError;

	switch (inAddress->mSelector) {
	case kAudioObjectPropertyBaseClass: {
		*(AudioClassID *)outData =
			(inObjectID == kObjectID_PlugIn) ? kAudioObjectClassID
			: (inObjectID == kObjectID_Box)  ? kAudioBoxClassID
			: (inObjectID == kObjectID_Device)
				? kAudioDeviceClassID
				: kAudioStreamClassID;
		*outDataSize = sizeof(AudioClassID);
		return kAudioHardwareNoError;
	}
	case kAudioObjectPropertyClass: {
		*(AudioClassID *)outData =
			(inObjectID == kObjectID_PlugIn)	 ? kAudioPlugInClassID
			: (inObjectID == kObjectID_Box)		 ? kAudioBoxClassID
			: (inObjectID == kObjectID_Device)	 ? kAudioDeviceClassID
							 : kAudioStreamClassID;
		*outDataSize = sizeof(AudioClassID);
		return kAudioHardwareNoError;
	}
	case kAudioObjectPropertyOwner: {
		*(AudioObjectID *)outData =
			(inObjectID == kObjectID_PlugIn)   ? kAudioObjectSystemObject
			: (inObjectID == kObjectID_Box)	   ? kObjectID_PlugIn
			: (inObjectID == kObjectID_Device) ? kObjectID_Box
							   : kObjectID_Device;
		*outDataSize = sizeof(AudioObjectID);
		return kAudioHardwareNoError;
	}
	case kAudioObjectPropertyManufacturer:
		*(CFStringRef *)outData = CFSTR("OBS WhatsApp Bridge");
		*outDataSize = sizeof(CFStringRef);
		return kAudioHardwareNoError;
	case kAudioObjectPropertyName:
		if (inObjectID == kObjectID_Device || inObjectID == kObjectID_Box)
			*(CFStringRef *)outData = CFSTR_DEVICE_NAME;
		else if (inObjectID == kObjectID_Stream_Input)
			*(CFStringRef *)outData = CFSTR_INPUT_NAME;
		else
			*(CFStringRef *)outData = CFSTR_OUTPUT_NAME;
		*outDataSize = sizeof(CFStringRef);
		return kAudioHardwareNoError;
	case kAudioObjectPropertyModelName:
		*(CFStringRef *)outData = CFSTR_DEVICE_MODEL;
		*outDataSize = sizeof(CFStringRef);
		return kAudioHardwareNoError;
	case kAudioObjectPropertyOwnedObjects:
	case kAudioPlugInPropertyBoxList:
	case kAudioPlugInPropertyDeviceList:
	case kAudioBoxPropertyDeviceList: {
		AudioObjectID *ids = (AudioObjectID *)outData;
		if (inObjectID == kObjectID_PlugIn) {
			ids[0] = (inAddress->mSelector == kAudioPlugInPropertyDeviceList)
					 ? kObjectID_Device
					 : kObjectID_Box;
			*outDataSize = sizeof(AudioObjectID);
		} else if (inObjectID == kObjectID_Box) {
			ids[0] = kObjectID_Device;
			*outDataSize = sizeof(AudioObjectID);
		} else {
			ids[0] = kObjectID_Stream_Input;
			ids[1] = kObjectID_Stream_Output;
			*outDataSize = sizeof(AudioObjectID) * 2;
		}
		return kAudioHardwareNoError;
	}
	case kAudioDevicePropertyStreams: {
		AudioObjectID *ids = (AudioObjectID *)outData;
		if (inAddress->mScope == kAudioObjectPropertyScopeInput) {
			ids[0] = kObjectID_Stream_Input;
			*outDataSize = sizeof(AudioObjectID);
		} else if (inAddress->mScope == kAudioObjectPropertyScopeOutput) {
			ids[0] = kObjectID_Stream_Output;
			*outDataSize = sizeof(AudioObjectID);
		} else {
			ids[0] = kObjectID_Stream_Input;
			ids[1] = kObjectID_Stream_Output;
			*outDataSize = sizeof(AudioObjectID) * 2;
		}
		return kAudioHardwareNoError;
	}
	case kAudioDevicePropertyDeviceUID:
		*(CFStringRef *)outData = CFSTR_DEVICE_UID;
		*outDataSize = sizeof(CFStringRef);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyModelUID:
		*(CFStringRef *)outData = CFSTR_DEVICE_MODEL;
		*outDataSize = sizeof(CFStringRef);
		return kAudioHardwareNoError;
	case kAudioBoxPropertyBoxUID:
		*(CFStringRef *)outData = CFSTR_BOX_UID;
		*outDataSize = sizeof(CFStringRef);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyTransportType:
	case kAudioBoxPropertyTransportType:
		*(UInt32 *)outData = kAudioDeviceTransportTypeVirtual;
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyRelatedDevices:
		*(AudioObjectID *)outData = kObjectID_Device;
		*outDataSize = sizeof(AudioObjectID);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyClockDomain:
		*(UInt32 *)outData = 0;
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyDeviceIsAlive:
	case kAudioDevicePropertyDeviceCanBeDefaultDevice:
	case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
	case kAudioStreamPropertyIsActive:
	case kAudioBoxPropertyHasAudio:
	case kAudioBoxPropertyAcquired:
		*(UInt32 *)outData = 1;
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyDeviceIsRunning:
		*(UInt32 *)outData = g_state.device_running ? 1 : 0;
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyIsHidden:
	case kAudioBoxPropertyHasVideo:
	case kAudioBoxPropertyHasMIDI:
	case kAudioBoxPropertyIsProtected:
	case kAudioBoxPropertyAcquisitionFailed:
		*(UInt32 *)outData = 0;
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyLatency:
	case kAudioStreamPropertyLatency:
		*(UInt32 *)outData = 0;
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyNominalSampleRate:
		*(Float64 *)outData = OBS_BRIDGE_SAMPLE_RATE;
		*outDataSize = sizeof(Float64);
		return kAudioHardwareNoError;
	case kAudioDevicePropertyAvailableNominalSampleRates: {
		AudioValueRange *r = (AudioValueRange *)outData;
		r->mMinimum = OBS_BRIDGE_SAMPLE_RATE;
		r->mMaximum = OBS_BRIDGE_SAMPLE_RATE;
		*outDataSize = sizeof(AudioValueRange);
		return kAudioHardwareNoError;
	}
	case kAudioDevicePropertyPreferredChannelsForStereo: {
		UInt32 *ch = (UInt32 *)outData;
		ch[0] = 1;
		ch[1] = 2;
		*outDataSize = sizeof(UInt32) * 2;
		return kAudioHardwareNoError;
	}
	case kAudioDevicePropertyPreferredChannelLayout: {
		AudioChannelLayout *layout = (AudioChannelLayout *)outData;
		layout->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
		layout->mChannelBitmap = 0;
		layout->mNumberChannelDescriptions = 2;
		layout->mChannelDescriptions[0].mChannelLabel = kAudioChannelLabel_Left;
		layout->mChannelDescriptions[1].mChannelLabel = kAudioChannelLabel_Right;
		*outDataSize = offsetof(AudioChannelLayout, mChannelDescriptions) +
			       sizeof(AudioChannelDescription) * 2;
		return kAudioHardwareNoError;
	}
	case kAudioObjectPropertyControlList:
		*outDataSize = 0;
		return kAudioHardwareNoError;
	case kAudioStreamPropertyDirection:
		*(UInt32 *)outData = (inObjectID == kObjectID_Stream_Input) ? 1 : 0;
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioStreamPropertyTerminalType:
		*(UInt32 *)outData = (inObjectID == kObjectID_Stream_Input)
					     ? kAudioStreamTerminalTypeMicrophone
					     : kAudioStreamTerminalTypeSpeaker;
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioStreamPropertyStartingChannel:
		*(UInt32 *)outData = 1;
		*outDataSize = sizeof(UInt32);
		return kAudioHardwareNoError;
	case kAudioStreamPropertyVirtualFormat:
	case kAudioStreamPropertyPhysicalFormat: {
		*(AudioStreamBasicDescription *)outData = stereo_asbd();
		*outDataSize = sizeof(AudioStreamBasicDescription);
		return kAudioHardwareNoError;
	}
	case kAudioStreamPropertyAvailableVirtualFormats:
	case kAudioStreamPropertyAvailablePhysicalFormats: {
		AudioStreamRangedDescription *rd = (AudioStreamRangedDescription *)outData;
		rd->mFormat = stereo_asbd();
		rd->mSampleRateRange.mMinimum = OBS_BRIDGE_SAMPLE_RATE;
		rd->mSampleRateRange.mMaximum = OBS_BRIDGE_SAMPLE_RATE;
		*outDataSize = sizeof(AudioStreamRangedDescription);
		return kAudioHardwareNoError;
	}
	case kAudioPlugInPropertyTranslateUIDToBox:
		if (inQualifierDataSize == sizeof(CFStringRef) && inQualifierData &&
		    CFEqual(*(CFStringRef *)inQualifierData, CFSTR_BOX_UID)) {
			*(AudioObjectID *)outData = kObjectID_Box;
			*outDataSize = sizeof(AudioObjectID);
			return kAudioHardwareNoError;
		}
		*(AudioObjectID *)outData = kAudioObjectUnknown;
		*outDataSize = sizeof(AudioObjectID);
		return kAudioHardwareNoError;
	case kAudioPlugInPropertyTranslateUIDToDevice:
		if (inQualifierDataSize == sizeof(CFStringRef) && inQualifierData &&
		    CFEqual(*(CFStringRef *)inQualifierData, CFSTR_DEVICE_UID)) {
			*(AudioObjectID *)outData = kObjectID_Device;
			*outDataSize = sizeof(AudioObjectID);
			return kAudioHardwareNoError;
		}
		*(AudioObjectID *)outData = kAudioObjectUnknown;
		*outDataSize = sizeof(AudioObjectID);
		return kAudioHardwareNoError;
	case kAudioObjectPropertyCustomPropertyInfoList:
		*outDataSize = 0;
		return kAudioHardwareNoError;
	default:
		(void)inDataSize;
		return kAudioHardwareUnknownPropertyError;
	}
}

static OSStatus OB_SetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID,
				   pid_t inClientProcessID,
				   const AudioObjectPropertyAddress *inAddress,
				   UInt32 inQualifierDataSize, const void *inQualifierData,
				   UInt32 inDataSize, const void *inData)
{
	(void)inDriver;
	(void)inObjectID;
	(void)inClientProcessID;
	(void)inAddress;
	(void)inQualifierDataSize;
	(void)inQualifierData;
	(void)inDataSize;
	(void)inData;
	return kAudioHardwareUnknownPropertyError;
}

#pragma mark - IO

static OSStatus OB_StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID,
			   UInt32 inClientID)
{
	(void)inDriver;
	(void)inDeviceObjectID;
	(void)inClientID;
	g_state.device_running = true;
	atomic_store(&g_state.host_ticks, mach_absolute_time());
	return kAudioHardwareNoError;
}

static OSStatus OB_StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID,
			  UInt32 inClientID)
{
	(void)inDriver;
	(void)inDeviceObjectID;
	(void)inClientID;
	g_state.device_running = false;
	return kAudioHardwareNoError;
}

static OSStatus OB_GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver,
				    AudioObjectID inDeviceObjectID, UInt32 inClientID,
				    Float64 *outSampleTime, UInt64 *outHostTime, UInt64 *outSeed)
{
	(void)inDriver;
	(void)inDeviceObjectID;
	(void)inClientID;
	static Float64 sample_time;
	static mach_timebase_info_data_t tb;
	if (tb.denom == 0)
		mach_timebase_info(&tb);

	UInt64 now = mach_absolute_time();
	UInt64 start = atomic_load(&g_state.host_ticks);
	double ns = (double)(now - start) * (double)tb.numer / (double)tb.denom;
	sample_time = ns * OBS_BRIDGE_SAMPLE_RATE / 1.0e9;

	*outSampleTime = sample_time;
	*outHostTime = now;
	*outSeed = 1;
	return kAudioHardwareNoError;
}

static OSStatus OB_WillDoIOOperation(AudioServerPlugInDriverRef inDriver,
				     AudioObjectID inDeviceObjectID, UInt32 inClientID,
				     UInt32 inOperationID, Boolean *outWillDo,
				     Boolean *outWillDoInPlace)
{
	(void)inDriver;
	(void)inDeviceObjectID;
	(void)inClientID;
	Boolean do_it = (inOperationID == kAudioServerPlugInIOOperationWriteMix ||
			 inOperationID == kAudioServerPlugInIOOperationReadInput);
	*outWillDo = do_it;
	*outWillDoInPlace = true;
	return kAudioHardwareNoError;
}

static OSStatus OB_BeginIOOperation(AudioServerPlugInDriverRef inDriver,
				    AudioObjectID inDeviceObjectID, UInt32 inClientID,
				    UInt32 inOperationID, UInt32 inIOBufferFrameSize,
				    const AudioServerPlugInIOCycleInfo *inIOCycleInfo)
{
	(void)inDriver;
	(void)inDeviceObjectID;
	(void)inClientID;
	(void)inOperationID;
	(void)inIOBufferFrameSize;
	(void)inIOCycleInfo;
	return kAudioHardwareNoError;
}

static OSStatus OB_DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID,
				 AudioObjectID inStreamObjectID, UInt32 inClientID,
				 UInt32 inOperationID, UInt32 inIOBufferFrameSize,
				 const AudioServerPlugInIOCycleInfo *inIOCycleInfo,
				 void *ioMainBuffer, void *ioSecondaryBuffer)
{
	(void)inDriver;
	(void)inDeviceObjectID;
	(void)inStreamObjectID;
	(void)inClientID;
	(void)inIOCycleInfo;
	(void)ioSecondaryBuffer;

	if (inOperationID == kAudioServerPlugInIOOperationWriteMix) {
		OBSBridge_RingWrite((const Float32 *)ioMainBuffer, inIOBufferFrameSize);
	} else if (inOperationID == kAudioServerPlugInIOOperationReadInput) {
		OBSBridge_RingRead((Float32 *)ioMainBuffer, inIOBufferFrameSize);
	}
	return kAudioHardwareNoError;
}

static OSStatus OB_EndIOOperation(AudioServerPlugInDriverRef inDriver,
				  AudioObjectID inDeviceObjectID, UInt32 inClientID,
				  UInt32 inOperationID, UInt32 inIOBufferFrameSize,
				  const AudioServerPlugInIOCycleInfo *inIOCycleInfo)
{
	(void)inDriver;
	(void)inDeviceObjectID;
	(void)inClientID;
	(void)inOperationID;
	(void)inIOBufferFrameSize;
	(void)inIOCycleInfo;
	return kAudioHardwareNoError;
}
