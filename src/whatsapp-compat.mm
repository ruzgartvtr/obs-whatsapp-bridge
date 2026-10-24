#import "whatsapp-compat.hpp"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#include <obs-module.h>

#include <sys/stat.h>
#include <unistd.h>

namespace obs_whatsapp_bridge {
namespace {

NSString *whatsapp_path()
{
	NSArray<NSString *> *candidates = @[
		@"/Applications/WhatsApp.app",
		[@"~/Applications/WhatsApp.app" stringByExpandingTildeInPath],
	];
	for (NSString *path in candidates) {
		if ([[NSFileManager defaultManager] fileExistsAtPath:path])
			return path;
	}
	/* Mac App Store package id */
	NSString *byId = [[NSWorkspace sharedWorkspace]
		URLForApplicationWithBundleIdentifier:@"net.whatsapp.WhatsApp"]
				 .path;
	if (byId.length)
		return byId;
	return nil;
}

bool file_exists(const char *path)
{
	struct stat st;
	return path && stat(path, &st) == 0;
}

} // namespace

WhatsAppStatus probe_whatsapp()
{
	WhatsAppStatus st;
	NSString *path = whatsapp_path();
	if (!path) {
		st.message = "WhatsApp.app bulunamadı. App Store veya whatsapp.com’dan kurun.";
		return st;
	}
	st.installed = true;
	st.app_path = path.UTF8String;

	/* Heuristic: ad-hoc / unsigned helpers often lack a stable TeamIdentifier. */
	NSString *helper = [path stringByAppendingPathComponent:
					 @"Contents/Frameworks/WhatsApp Helper (Renderer).app"];
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/codesign";
	task.arguments = @[ @"-dv", @"--verbose=2", helper ?: path ];
	NSPipe *errPipe = [NSPipe pipe];
	task.standardError = errPipe;
	task.standardOutput = [NSPipe pipe];
	@try {
		[task launch];
		[task waitUntilExit];
	} @catch (NSException *) {
		st.message = "codesign okunamadı.";
		return st;
	}
	NSData *data = [[errPipe fileHandleForReading] readDataToEndOfFile];
	NSString *out = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
	BOOL adhoc = [out containsString:@"Signature=adhoc"] ||
		     [out containsString:@"flags=0x2(adhoc)"] ||
		     ![out containsString:@"Authority="];
	st.virtual_cam_likely_enabled = adhoc;
	if (adhoc) {
		st.message =
			"WhatsApp sanal kamera için yeniden imzalanmış görünüyor. "
			"Görüntülü aramada kamera listesinden OBS Virtual Camera / NDI seçin.";
	} else {
		st.message =
			"WhatsApp hâlâ orijinal imzalı — sanal kamera listede çıkmayabilir. "
			"“WhatsApp sanal kamera erişimini aç” düğmesini kullanın.";
	}
	return st;
}

std::string bundled_enable_script_path()
{
	const char *path = obs_get_module_data_path(obs_current_module());
	if (!path)
		return {};
	std::string candidate = std::string(path) + "/enable-whatsapp.sh";
	if (file_exists(candidate.c_str()))
		return candidate;
	/* Dev / repo layout */
	candidate = std::string(path) + "/../../../scripts/enable-whatsapp.sh";
	if (file_exists(candidate.c_str()))
		return candidate;
	return "/usr/local/share/obs-whatsapp-bridge/enable-whatsapp.sh";
}

bool enable_whatsapp_virtual_camera(std::string &error_out)
{
	NSString *app = whatsapp_path();
	if (!app) {
		error_out = "WhatsApp.app bulunamadı.";
		return false;
	}

	std::string script = bundled_enable_script_path();
	NSString *scriptPath = nil;
	if (!script.empty() && file_exists(script.c_str())) {
		scriptPath = [NSString stringWithUTF8String:script.c_str()];
	}

	NSString *shell;
	if (scriptPath) {
		shell = [NSString stringWithFormat:@"'%@' '%@'", scriptPath, app];
	} else {
		/* Inline fallback — same entitlements as scripts/enable-whatsapp.sh */
		shell = [NSString stringWithFormat:
					 @"WA='%@'; "
					 @"ENT=$(mktemp -t wa-ent); "
					 @"printf '%%s\\n' "
					 @"'<?xml version=\"1.0\" encoding=\"UTF-8\"?>' "
					 @"'<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
					 @"\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">' "
					 @"'<plist version=\"1.0\"><dict>' "
					 @"'<key>com.apple.security.cs.disable-library-validation</key><true/>' "
					 @"'</dict></plist>' > \"$ENT\"; "
					 @"codesign --entitlements \"$ENT\" -f -s - \"$WA\"; "
					 @"for h in \"WhatsApp Helper\" \"WhatsApp Helper (GPU)\" "
					 @"\"WhatsApp Helper (Plugin)\" \"WhatsApp Helper (Renderer)\"; do "
					 @"P=\"$WA/Contents/Frameworks/$h.app\"; "
					 @"[ -d \"$P\" ] && codesign --entitlements \"$ENT\" -f -s - \"$P\"; "
					 @"done; "
					 @"rm -f \"$ENT\"; "
					 @"tccutil reset Camera net.whatsapp.WhatsApp 2>/dev/null; true",
					 app];
	}

	NSString *appleScript = [NSString
		stringWithFormat:
			@"do shell script \"%@\" with administrator privileges",
			[[shell stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
				stringByReplacingOccurrencesOfString:@"\""
							  withString:@"\\\""]];

	NSAppleScript *as = [[NSAppleScript alloc] initWithSource:appleScript];
	NSDictionary *err = nil;
	NSAppleEventDescriptor *result = [as executeAndReturnError:&err];
	if (!result) {
		NSString *msg = err[NSAppleScriptErrorMessage] ?: @"Bilinmeyen hata";
		error_out = msg.UTF8String;
		blog(LOG_ERROR, "[whatsapp-bridge] enable WhatsApp failed: %s", error_out.c_str());
		return false;
	}

	blog(LOG_INFO, "[whatsapp-bridge] WhatsApp virtual-camera entitlements applied for %s",
	     app.UTF8String);
	return true;
}

} // namespace obs_whatsapp_bridge
