#import <Foundation/Foundation.h>

#define DRIVER_NAME     @"360Controller.kext"

static NSDictionary *infoPlistAttributes = nil;

static NSString* GetDriverDirectory(void)
{
    NSArray *data = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSSystemDomainMask, YES);
    return [[data objectAtIndex:0] stringByAppendingPathComponent:@"Extensions"];
}

static NSString* GetDriverConfigPath(NSString *driver)
{
    NSString *root = GetDriverDirectory();
    NSString *driverPath = [root stringByAppendingPathComponent:driver];
    NSString *contents = [driverPath stringByAppendingPathComponent:@"Contents"];
    return [contents stringByAppendingPathComponent:@"Info.plist"];
}

static id ReadDriverConfig(NSString *driver)
{
    NSString *filename;
    NSError *error = nil;
    NSData *data;
    NSDictionary *config;
    
    filename = GetDriverConfigPath(driver);
    infoPlistAttributes = [[[NSFileManager defaultManager] attributesOfItemAtPath:filename error:&error] retain];
    if (infoPlistAttributes == nil)
    {
        NSLog(@"Warning: Failed to read attributes of '%@': %@",
              filename, error);
    }
    data = [NSData dataWithContentsOfFile:filename];
    config = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:0 format:NULL errorDescription:NULL];
    return config;
}

static void WriteDriverConfig(NSString *driver, id config)
{
    NSString *filename;
    NSString *errorString;
    NSData *data;
    
    filename = GetDriverConfigPath(driver);
    errorString = nil;
    data = [NSPropertyListSerialization dataFromPropertyList:config format:NSPropertyListXMLFormat_v1_0 errorDescription:&errorString];
    if (data == nil)
        NSLog(@"Error writing config for driver: %@", errorString);
    [errorString release];
    if (![data writeToFile:filename atomically:NO])
        NSLog(@"Failed to write file!");
    if (infoPlistAttributes != nil)
    {
        NSError *error = nil;
        if (![[NSFileManager defaultManager] setAttributes:infoPlistAttributes ofItemAtPath:filename error:&error])
        {
            NSLog(@"Error setting attributes on '%@': %@",
                  filename, error);
        }
    }
}

static void ScrubDevices(NSMutableDictionary *devices)
{
    NSMutableArray *deviceKeys;
    NSArray *keys;
    
    deviceKeys = [NSMutableArray arrayWithCapacity:10];
    
    // Find all the devices in the list
    keys = [devices allKeys];
    for (NSString *key in keys)
    {
        NSDictionary *device = [devices objectForKey:key];
        if ([(NSString*)[device objectForKey:@"IOClass"] compare:@"Xbox360Peripheral"] == NSOrderedSame)
            [deviceKeys addObject:key];
    }
    
    // Scrub all found devices
    for (NSString *key in deviceKeys)
        [devices removeObjectForKey:key];
}

static id MakeMutableCopy(id object)
{
    return [(id<NSObject>)CFPropertyListCreateDeepCopy(
                    kCFAllocatorDefault,
                    (CFTypeRef)object,
                    kCFPropertyListMutableContainers) autorelease];
}

static void AddDevice(NSMutableDictionary *personalities, NSString *name, int vendor, int product)
{
    NSMutableDictionary *controller;
    
    controller = [NSMutableDictionary dictionaryWithCapacity:10];
    
    // Standard 
    [controller setObject:@"com.mice.driver.Xbox360Controller"
                   forKey:@"CFBundleIdentifier"];
    [controller setObject:[NSDictionary dictionaryWithObject:@"360Controller.kext/Contents/PlugIns/Feedback360.plugin"
                                                      forKey:@"F4545CE5-BF5B-11D6-A4BB-0003933E3E3E"]
                   forKey:@"IOCFPlugInTypes"];
    [controller setObject:@"Xbox360Peripheral"
                   forKey:@"IOClass"];
    [controller setObject:@"IOUSBDevice"
                   forKey:@"IOProviderClass"];
    [controller setObject:[NSNumber numberWithInt:65535]
                   forKey:@"IOKitDebug"];
    
    // Device-specific
    [controller setObject:[NSNumber numberWithInt:vendor]
                   forKey:@"idVendor"];
    [controller setObject:[NSNumber numberWithInt:product]
                   forKey:@"idProduct"];
    
    // Add it to the tree
    [personalities setObject:controller
                      forKey:name];
}

static void AddDevices(NSMutableDictionary *personalities, int argc, const char *argv[])
{
    int i, count;
    
    count = (argc - 1) / 3;
    for (i = 0; i < count; i++)
    {
        NSString *name = [NSString stringWithCString:argv[(i * 3) + 1] encoding:NSUTF8StringEncoding];
        int vendor = atoi(argv[(i * 3) + 2]);
        int product = atoi(argv[(i * 3) + 3]);
        AddDevice(personalities, name, vendor, product);
    }
}

int main (int argc, const char * argv[]) {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    NSDictionary *config = ReadDriverConfig(DRIVER_NAME);
    if (argc == 1)
    {
        // Print out current types
        NSDictionary *types;
        NSArray *keys;
        
        types = [config objectForKey:@"IOKitPersonalities"];
        keys = [types allKeys];
        for (NSString *key in keys)
        {
            NSDictionary *device = [types objectForKey:key];
            if ([(NSString*)[device objectForKey:@"IOClass"] compare:@"Xbox360Peripheral"] != NSOrderedSame)
                continue;
            fprintf(stdout, "%s,%i,%i\n",
                    [key UTF8String],
                    [[device objectForKey:@"idVendor"] intValue],
                    [[device objectForKey:@"idProduct"] intValue]);
        }
    }
    else if (((argc - 1) % 3) == 0)
    {
        NSMutableDictionary *saving;
        NSMutableDictionary *devices;
        
        saving = MakeMutableCopy(config);
        devices = [saving objectForKey:@"IOKitPersonalities"];
        ScrubDevices(devices);
        AddDevices(devices, argc, argv);
        WriteDriverConfig(DRIVER_NAME, saving);
    }
    else
        NSLog(@"Invalid number of parameters (%i)", argc);
    
    [pool drain];
    return 0;
}
