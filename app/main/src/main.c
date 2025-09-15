// app/main/src/main.c

#include <zephyr/kernel.h>

#define APP_LOG_MODULE MAIN
#include "logger.h"
LOG_MODULE_REGISTER(APP_LOG_MODULE, APP_LOG_LEVEL);

#include "main.h"

int main(void)
{
    LOG_INFO("Hello, Zephyr!");

    while (1)
    {
        LOG_DEBUG("Main loop iteration");
        k_sleep(K_SECONDS(5));
    }

    return 0;
}