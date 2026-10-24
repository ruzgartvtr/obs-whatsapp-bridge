#pragma once

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>

#include <stdatomic.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
	kObjectID_PlugIn = kAudioObjectPlugInObject,
	kObjectID_Box = 2,
	kObjectID_Device = 3,
	kObjectID_Stream_Input = 4,
	kObjectID_Stream_Output = 5,
	kObjectID_Volume_Input_Master = 6,
	kObjectID_Volume_Output_Master = 7,
};

#define OBS_BRIDGE_SAMPLE_RATE 48000.0
#define OBS_BRIDGE_CHANNELS 2
#define OBS_BRIDGE_RING_SECONDS 2
#define OBS_BRIDGE_RING_FRAMES ((UInt32)(OBS_BRIDGE_SAMPLE_RATE * OBS_BRIDGE_RING_SECONDS))

typedef struct {
	AudioServerPlugInHostRef host;
	atomic_uint_fast64_t host_ticks;
	Float32 volume;
	bool device_running;
	Float32 *ring; /* interleaved stereo, OBS_BRIDGE_RING_FRAMES * channels */
	atomic_uint_fast64_t write_pos;
	atomic_uint_fast64_t read_pos;
} OBSBridgeState;

extern OBSBridgeState g_state;

void OBSBridge_RingInit(void);
void OBSBridge_RingTeardown(void);
void OBSBridge_RingWrite(const Float32 *src, UInt32 frames);
void OBSBridge_RingRead(Float32 *dst, UInt32 frames);

#ifdef __cplusplus
}
#endif
