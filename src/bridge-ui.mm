#import "bridge-ui.hpp"
#import "audio-bridge.hpp"
#import "whatsapp-compat.hpp"

#import <AppKit/AppKit.h>
#import <obs-frontend-api.h>
#import <obs-module.h>

@interface OBSWhatsAppBridgePanel : NSObject
- (void)show;
@end

@implementation OBSWhatsAppBridgePanel {
	NSWindow *_window;
	NSTextField *_statusLabel;
	NSButton *_toggleButton;
	NSButton *_whatsappButton;
}

- (void)show
{
	if (_window) {
		[self refresh];
		[_window makeKeyAndOrderFront:nil];
		[NSApp activateIgnoringOtherApps:YES];
		return;
	}

	NSRect frame = NSMakeRect(0, 0, 460, 280);
	_window = [[NSWindow alloc]
		initWithContentRect:frame
			  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
			    backing:NSBackingStoreBuffered
			      defer:NO];
	_window.title = @"OBS WhatsApp Bridge";
	_window.releasedWhenClosed = NO;

	NSView *content = _window.contentView;

	NSTextField *title = [self labelWithText:@"WhatsApp için sanal kamera + ses"
					   frame:NSMakeRect(20, 230, 420, 24)
					    bold:YES];
	[content addSubview:title];

	NSTextField *help = [self
		labelWithText:
			@"OBS Sanal Kamerası görüntü taşır; bu eklenti program sesini "
			 @"“OBS Bridge Mic”e yollar. WhatsApp’ta kamera: OBS Virtual Camera, "
			 @"mikrofon: OBS Bridge Mic."
			frame:NSMakeRect(20, 160, 420, 60)
			 bold:NO];
	help.maximumNumberOfLines = 4;
	[content addSubview:help];

	_statusLabel = [self labelWithText:@"" frame:NSMakeRect(20, 100, 420, 50) bold:NO];
	_statusLabel.maximumNumberOfLines = 3;
	[content addSubview:_statusLabel];

	_toggleButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 55, 200, 32)];
	_toggleButton.bezelStyle = NSBezelStyleRounded;
	_toggleButton.target = self;
	_toggleButton.action = @selector(onToggle:);
	[content addSubview:_toggleButton];

	_whatsappButton = [[NSButton alloc] initWithFrame:NSMakeRect(230, 55, 210, 32)];
	_whatsappButton.bezelStyle = NSBezelStyleRounded;
	_whatsappButton.title = @"WhatsApp sanal kamerayı aç";
	_whatsappButton.target = self;
	_whatsappButton.action = @selector(onWhatsApp:);
	[content addSubview:_whatsappButton];

	NSButton *vcamHint = [[NSButton alloc] initWithFrame:NSMakeRect(20, 18, 420, 28)];
	vcamHint.bezelStyle = NSBezelStyleRounded;
	vcamHint.title = @"OBS Sanal Kamerayı başlat (hatırlatma)";
	vcamHint.target = self;
	vcamHint.action = @selector(onVirtualCamHint:);
	[content addSubview:vcamHint];

	[self refresh];
	[_window center];
	[_window makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
}

- (NSTextField *)labelWithText:(NSString *)text frame:(NSRect)frame bold:(BOOL)bold
{
	NSTextField *f = [[NSTextField alloc] initWithFrame:frame];
	f.stringValue = text;
	f.bezeled = NO;
	f.drawsBackground = NO;
	f.editable = NO;
	f.selectable = YES;
	f.font = bold ? [NSFont boldSystemFontOfSize:13] : [NSFont systemFontOfSize:12];
	return f;
}

- (void)refresh
{
	auto &bridge = obs_whatsapp_bridge::AudioBridge::instance();
	auto wa = obs_whatsapp_bridge::probe_whatsapp();

	NSString *audio = [NSString stringWithUTF8String:bridge.status_text().c_str()];
	NSString *waMsg = [NSString stringWithUTF8String:wa.message.c_str()];
	_statusLabel.stringValue = [NSString stringWithFormat:@"%@\n%@", audio, waMsg];

	_toggleButton.title = bridge.is_running() ? @"Ses köprüsünü kapat" : @"Ses köprüsünü aç";
}

- (void)onToggle:(id)sender
{
	(void)sender;
	auto &bridge = obs_whatsapp_bridge::AudioBridge::instance();
	if (bridge.is_running()) {
		bridge.stop();
	} else {
		if (!bridge.start()) {
			NSAlert *alert = [[NSAlert alloc] init];
			alert.messageText = @"Sanal mikrofon bulunamadı";
			alert.informativeText =
				@"Önce sanal mikrofonu kurun:\n\n"
				@"  ./scripts/install-audio-driver.sh\n\n"
				@"veya: brew install blackhole-2ch\n\n"
				@"Sonra OBS’i yeniden başlatıp tekrar deneyin.";
			[alert runModal];
		}
	}
	[self refresh];
}

- (void)onWhatsApp:(id)sender
{
	(void)sender;
	std::string err;
	if (!obs_whatsapp_bridge::enable_whatsapp_virtual_camera(err)) {
		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = @"WhatsApp ayarı başarısız";
		alert.informativeText = [NSString
			stringWithFormat:@"%s\n\nElle: scripts/enable-whatsapp.sh", err.c_str()];
		[alert runModal];
	} else {
		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = @"WhatsApp hazır";
		alert.informativeText =
			@"WhatsApp’ı tamamen kapatıp yeniden açın.\n"
			@"Görüntülü aramada kamera: OBS Virtual Camera "
			@"(veya NDI Video), mikrofon: OBS Bridge Mic.";
		[alert runModal];
	}
	[self refresh];
}

- (void)onVirtualCamHint:(id)sender
{
	(void)sender;
	/* OBS frontend API: start virtual camera when it is not already running. */
	if (!obs_frontend_virtualcam_active())
		obs_frontend_start_virtualcam();
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = @"Sanal kamera";
	alert.informativeText =
		@"OBS’te Controls → Start Virtual Camera kullanın (veya az önce başlatıldı).\n"
		@"WhatsApp görüntülü aramada kamera listesinden “OBS Virtual Camera” seçin.";
	[alert runModal];
	[self refresh];
}

@end

namespace obs_whatsapp_bridge {
namespace {

OBSWhatsAppBridgePanel *g_panel = nil;

void tools_menu_clicked(void *)
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!g_panel)
			g_panel = [[OBSWhatsAppBridgePanel alloc] init];
		[g_panel show];
	});
}

} // namespace

void show_bridge_panel()
{
	tools_menu_clicked(nullptr);
}

void register_frontend_tools()
{
	obs_frontend_add_tools_menu_item("WhatsApp Bridge", tools_menu_clicked, nullptr);
}

void unregister_frontend_tools()
{
	if (AudioBridge::instance().is_running())
		AudioBridge::instance().stop();
	g_panel = nil;
}

} // namespace obs_whatsapp_bridge
