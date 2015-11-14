#import <Cocoa/Cocoa.h>

int macosx_ibook_fnswitch(int setting);
int macosx_fnswitch(int setting);
void SigPipeHandler(int s);

#include "util.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/IOReturn.h>
#include <ApplicationServices/ApplicationServices.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDParameter.h>


#define kMyDriversKeyboardClassName     "AppleADBKeyboard"
#define kfnSwitchError                  200
#define kfnAppleMode            0
#define kfntheOtherMode         1

#ifndef kIOHIDFKeyModeKey
#define kIOHIDFKeyModeKey    "HIDFKeyMode"
#endif

#include <signal.h>
#include <assert.h>
#include <pthread.h>
#include <sys/types.h>
#include <regex.h>
#include <stdio.h>

char* getFrontProcessName() {
    
    ProcessSerialNumber psn = { 0L, 0L };
    OSStatus err = GetFrontProcess(&psn);
    
    CFStringRef processNameCf = NULL;
    err = CopyProcessName(&psn, &processNameCf);
    long len = CFStringGetLength(processNameCf) + 1;
    char *processName = (char*) malloc(len);
    CFStringGetCString(processNameCf, processName, len, kCFStringEncodingASCII);
    return processName;
}

void* PosixThreadMainRoutine(void* data)
{
    
    regex_t regex;
    int reti;
    
    /* Compile regular expression */
    reti = regcomp(&regex, "^(iTerm|PhpStorm|muCommander)$", REG_EXTENDED);
    if( reti ){ fprintf(stderr, "Could not compile regex\n"); exit(1); }
    
    // Do some work here.
    char* processName;
    char* lastProcessName = 0;
    int setting = 0;
    for (;;) {
        
        processName = (char*) getFrontProcessName();
        if (lastProcessName != 0 && strcmp(processName, lastProcessName) == 0) {
            goto sleep;
        }
        lastProcessName = processName;
        /* Execute regular expression */
        reti = regexec(&regex, processName, 0, NULL, 0);
        if( !reti ){
            if (setting == 0) {
                setting = 1;
                macosx_fnswitch(1);
            }
        }
        else if( reti == REG_NOMATCH ){
            if (setting == 1) {
                setting = 0;
                macosx_fnswitch(0);
            }
        }
        else{
            char msgbuf[100];
            regerror(reti, &regex, msgbuf, sizeof(msgbuf));
            fprintf(stderr, "Regex match failed: %s\n", msgbuf);
            exit(1);
        }
        sleep:
        usleep(0.1e6);
    }
    free(processName);
    regfree(&regex);
    return NULL;
}

void LaunchThread()
{
    pthread_attr_t  attr;
    pthread_t       posixThreadID;
    int             returnVal;
    
    returnVal = pthread_attr_init(&attr);
    assert(!returnVal);
    returnVal = pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    assert(!returnVal);
    
    int     threadError = pthread_create(&posixThreadID, &attr, &PosixThreadMainRoutine, NULL);
    
    returnVal = pthread_attr_destroy(&attr);
    assert(!returnVal);
    if (threadError != 0)
    {
        // Report an error.
    }
}


void SignalHandler(int s)
{
    printf("SIGNAL: %n\n", s);
}


int main(int argc, const char * argv[])
{
    LaunchThread();
    signal(SIGABRT, SignalHandler);
    signal(SIGILL, SignalHandler);
    signal(SIGSEGV, SignalHandler);
    signal(SIGFPE, SignalHandler);
    signal(SIGBUS, SignalHandler);
    signal(SIGPIPE, SignalHandler);
    signal(SIGUSR2, SignalHandler);
    return NSApplicationMain(argc, argv);
}



int macosx_ibook_fnswitch(int setting)
{
    kern_return_t kr;
    mach_port_t mp;
    io_service_t so;
    /*io_name_t sn;*/
    io_connect_t dp;
    io_iterator_t it;
    CFDictionaryRef classToMatch;
    /*CFNumberRef   fnMode;*/
    unsigned int res, dummy;
    
    kr = IOMasterPort(bootstrap_port, &mp);
    if (kr != KERN_SUCCESS) return -1;
    
    classToMatch = IOServiceMatching(kIOHIDSystemClass);
    if (classToMatch == NULL) {
        return -1;
    }
    kr = IOServiceGetMatchingServices(mp, classToMatch, &it);
    if (kr != KERN_SUCCESS) return -1;
    
    so = IOIteratorNext(it);
    IOObjectRelease(it);
    
    if (!so) return -1;
    
    kr = IOServiceOpen(so, mach_task_self(), kIOHIDParamConnectType, &dp);
    if (kr != KERN_SUCCESS) return -1;
    
    kr = IOHIDGetParameter(dp, CFSTR(kIOHIDFKeyModeKey), sizeof(res),
                           &res, (IOByteCount *) &dummy);
    if (kr != KERN_SUCCESS) {
        IOServiceClose(dp);
        return -1;
    }
    
    if (setting == kfnAppleMode || setting == kfntheOtherMode) {
        dummy = setting;
        kr = IOHIDSetParameter(dp, CFSTR(kIOHIDFKeyModeKey),
                               &dummy, sizeof(dummy));
        if (kr != KERN_SUCCESS) {
            IOServiceClose(dp);
            return -1;
        }
    }
    
    IOServiceClose(dp);
    /* old setting... */
    
    return res;
}

int macosx_fnswitch(int setting)
{
    unsigned int res = -1;
    if (setting == 1) {
        res = macosx_ibook_fnswitch(1);
        CFPreferencesSetAppValue( CFSTR("fnState"), kCFBooleanTrue, CFSTR("com.apple.keyboard") );
        CFPreferencesAppSynchronize( CFSTR("com.apple.keyboard") );
        CFDictionaryKeyCallBacks keyCallbacks = {0, NULL, NULL, CFCopyDescription, CFEqual, NULL};
        CFDictionaryValueCallBacks valueCallbacks  = {0, NULL, NULL, CFCopyDescription, CFEqual};
        CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
        CFMutableDictionaryRef dictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
                                                                      &keyCallbacks, &valueCallbacks);
        CFDictionaryAddValue(dictionary, CFSTR("state"), kCFBooleanTrue);
        CFNotificationCenterPostNotification(center, CFSTR("com.apple.keyboard.fnstatedidchange"), NULL, dictionary, TRUE);
        printf("ON\n");
    } else {
        res = macosx_ibook_fnswitch(0);
        CFPreferencesSetAppValue( CFSTR("fnState"), kCFBooleanFalse, CFSTR("com.apple.keyboard") );
        CFPreferencesAppSynchronize( CFSTR("com.apple.keyboard") );
        CFDictionaryKeyCallBacks keyCallbacks = {0, NULL, NULL, CFCopyDescription, CFEqual, NULL};
        CFDictionaryValueCallBacks valueCallbacks  = {0, NULL, NULL, CFCopyDescription, CFEqual};
        CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
        CFMutableDictionaryRef dictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
                                                                      &keyCallbacks, &valueCallbacks);
        CFDictionaryAddValue(dictionary, CFSTR("state"), kCFBooleanFalse);
        CFNotificationCenterPostNotification(center, CFSTR("com.apple.keyboard.fnstatedidchange"), NULL, dictionary, TRUE);
        printf("OFF\n");
    }
    return res;
}