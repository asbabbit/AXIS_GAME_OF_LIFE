
#include "xaxidma.h"
#include "xparameters.h"
#include "xdebug.h"
#include "sleep.h"
#include "xaxidma_hw.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "xgpio.h"

// --- Address and Device ID Mappings from xparameters.h ---
#define DMA_BASE_ADDR           XPAR_AXI_DMA_0_BASEADDR
#define MEM_BASE_ADDR           XPAR_PS7_DDR_0_BASEADDRESS
#define GPIO_LOAD_BASE_ADDR     XPAR_XGPIO_1_BASEADDR   // 1-bit GPIO for load signal
#define GPIO_DATA_LO_BASE_ADDR  XPAR_XGPIO_0_BASEADDR   // 32-bit GPIO for lower half of data
#define GPIO_DATA_HI_BASE_ADDR  XPAR_XGPIO_2_BASEADDR   // 32-bit GPIO for upper half of data

// --- DMA and Buffer Definitions ---
#define RX_BUFFER_BASE          (MEM_BASE_ADDR + 0x400000)
#define MAX_PKT_LEN             0x8 // 8 bytes for a 64-bit state

// --- GPIO Channel Definitions ---
// All are single-channel GPIOs, so we always use Channel 1.
#define GPIO_CHANNEL            1

// --- Timeout Definitions ---
#define POLL_TIMEOUT_COUNTER    10000000U

// --- Function Prototypes ---
static int DmaSetup(const UINTPTR BaseAddress);
static int GpioSetup(XGpio *InstancePtr, const UINTPTR BaseAddress, const char* name);
static int PollDmaCompletion(void);
static void LoadInitialData(void);
static void PrintRxBuffer(void);

// --- Global Variables ---
static XAxiDma AxiDma;          // AXI DMA driver instance
static XGpio GpioLoad;          // AXI GPIO instance for the load signal
static XGpio GpioDataLo;        // AXI GPIO instance for the lower 32-bit data
static XGpio GpioDataHi;        // AXI GPIO instance for the upper 32-bit data
static u32 *RxBufferPtr = (u32 *)RX_BUFFER_BASE;

int main() {
    int status;

    xil_printf("--- Starting AXI DMA Transfer Loop ---\r\n");

    // Initialize all GPIO peripherals
    status = GpioSetup(&GpioLoad, GPIO_LOAD_BASE_ADDR, "Load");
    if (status != XST_SUCCESS) return XST_FAILURE;
    status = GpioSetup(&GpioDataLo, GPIO_DATA_LO_BASE_ADDR, "Data Low");
    if (status != XST_SUCCESS) return XST_FAILURE;
    status = GpioSetup(&GpioDataHi, GPIO_DATA_HI_BASE_ADDR, "Data High");
    if (status != XST_SUCCESS) return XST_FAILURE;

    // Set all GPIOs as outputs
    XGpio_SetDataDirection(&GpioLoad,    GPIO_CHANNEL, 0x0);
    XGpio_SetDataDirection(&GpioDataLo,  GPIO_CHANNEL, 0x0);
    XGpio_SetDataDirection(&GpioDataHi,  GPIO_CHANNEL, 0x0);

    // Initialize load signal to low
    XGpio_DiscreteWrite(&GpioLoad, GPIO_CHANNEL, 0x0);

    // Initialize the AXI DMA engine
    status = DmaSetup(DMA_BASE_ADDR);
    if (status != XST_SUCCESS) {
        xil_printf("DMA setup failed.\r\n");
        return XST_FAILURE;
    }
    xil_printf("DMA is initialized and ready.\r\n");

    // --- Initial Data Load and Transfer ---
    xil_printf("Loading initial 64-bit data into the custom IP via AXI GPIOs...\r\n");
    LoadInitialData();

    // Arm the DMA before sending the load pulse
    xil_printf("Arming DMA to receive initial data...\r\n");
    status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)RxBufferPtr, MAX_PKT_LEN, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("Initial DMA transfer start failed.\r\n");
        return XST_FAILURE;
    }
    xil_printf("DMA armed and ready to receive data.\r\n");

    // Pulse the load signal to start the stream
    xil_printf("Sending load pulse to custom IP...\r\n");
    XGpio_DiscreteWrite(&GpioLoad, GPIO_CHANNEL, 0x1);
    XGpio_DiscreteWrite(&GpioLoad, GPIO_CHANNEL, 0x0);
    xil_printf("Load pulse sent. Data should start streaming now.\r\n");

    // Wait for the initial DMA transfer to complete
    status = PollDmaCompletion();
    if (status != XST_SUCCESS) {
        xil_printf("Initial DMA transfer timed out or failed.\r\n");
        return XST_FAILURE;
    }
    Xil_DCacheInvalidateRange((UINTPTR)RxBufferPtr, MAX_PKT_LEN);
    xil_printf("Initial DMA transfer complete. Received initial generation:\r\n");
    PrintRxBuffer();

    // --- Continuous Loop for Subsequent Generations ---
    int generation_count = 1;
    while (1) {
        xil_printf("--- Generation %d ---\r\n", generation_count);

        // Re-initialize DMA in each loop
        status = DmaSetup(DMA_BASE_ADDR);
        if (status != XST_SUCCESS) {
            xil_printf("DMA setup failed for generation %d.\r\n", generation_count);
            return XST_FAILURE;
        }

        // Arm DMA for the next transfer
        status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)RxBufferPtr, MAX_PKT_LEN, XAXIDMA_DEVICE_TO_DMA);
        if (status != XST_SUCCESS) {
            xil_printf("DMA transfer start failed for generation %d.\r\n", generation_count);
            return XST_FAILURE;
        }

        // Wait for the DMA transfer to complete
        status = PollDmaCompletion();
        if (status != XST_SUCCESS) {
            xil_printf("DMA transfer timed out for generation %d. Exiting.\r\n", generation_count);
            return XST_FAILURE;
        }

        // Invalidate cache to read fresh data from memory and print
        Xil_DCacheInvalidateRange((UINTPTR)RxBufferPtr, MAX_PKT_LEN);
        PrintRxBuffer();

        generation_count++;
        // NOTE: The `sleep(1)` here is acceptable as it's outside the critical DMA-arming window.
        sleep(1);
    }
    return XST_SUCCESS;
}

// A generic GPIO setup function to reduce code repetition
static int GpioSetup(XGpio *InstancePtr, const UINTPTR BaseAddress, const char* name) {
    int status;
    XGpio_Config *config_ptr;

    config_ptr = XGpio_LookupConfig(BaseAddress);
    if (config_ptr == NULL) {
        xil_printf("GPIO %s config lookup failed.\r\n", name);
        return XST_FAILURE;
    }

    status = XGpio_CfgInitialize(InstancePtr, config_ptr, config_ptr->BaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("GPIO %s initialization failed.\r\n", name);
        return XST_FAILURE;
    }

    xil_printf("GPIO %s initialized successfully.\r\n", name);
    return XST_SUCCESS;
}

static int DmaSetup(const UINTPTR BaseAddress) {
    int status;
    XAxiDma_Config *config_ptr;

    config_ptr = XAxiDma_LookupConfig(BaseAddress);
    if (!config_ptr) {
        xil_printf("No config found for %x.\r\n", BaseAddress);
        return XST_FAILURE;
    }

    status = XAxiDma_CfgInitialize(&AxiDma, config_ptr);
    if (status != XST_SUCCESS) {
        xil_printf("Initialization failed %d.\r\n", status);
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(&AxiDma)) {
        xil_printf("Device configured as SG mode.\r\n");
        return XST_FAILURE;
    }

    XAxiDma_Reset(&AxiDma);
    while (!XAxiDma_ResetIsDone(&AxiDma)) {
        // Wait for reset to complete
    }

    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);

    return XST_SUCCESS;
}

static void LoadInitialData(void) {
    const u64 initial_data = 0x0000000000C06080;

    // Split the 64-bit data into two 32-bit values
    const u32 low_bits = (u32)(initial_data & 0xFFFFFFFF);
    const u32 high_bits = (u32)(initial_data >> 32);

    XGpio_DiscreteWrite(&GpioDataLo, GPIO_CHANNEL, low_bits);
    XGpio_DiscreteWrite(&GpioDataHi, GPIO_CHANNEL, high_bits);

    xil_printf("Initial data 0x%llx written to AXI GPIOs.\r\n", initial_data);
}

static int PollDmaCompletion() {
    u32 timeout = POLL_TIMEOUT_COUNTER;

    while (timeout) {
        if (!(XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA))) {
            break;
        }
        timeout--;
    }

    if (timeout == 0) {
        u32 status_reg = XAxiDma_IntrGetIrq(&AxiDma, XAXIDMA_DEVICE_TO_DMA);
        xil_printf("DMA timeout! Status: 0x%x\r\n", status_reg);
        if (status_reg & XAXIDMA_ERR_ALL_MASK) {
            xil_printf("DMA Error bits set: 0x%x\r\n", status_reg & XAXIDMA_ERR_ALL_MASK);
        }
        return XST_FAILURE;
    }

    u32 status_reg = XAxiDma_IntrGetIrq(&AxiDma, XAXIDMA_DEVICE_TO_DMA);
    if (status_reg & XAXIDMA_ERR_ALL_MASK) {
        xil_printf("DMA error detected during receive! Status: 0x%x\r\n", status_reg);
        return XST_FAILURE;
    }

    XAxiDma_IntrAckIrq(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    return XST_SUCCESS;
}

static void PrintRxBuffer(void) {
    const u8* data_byte = (const u8*)RxBufferPtr;
    xil_printf("Data received in DDR: ");
    for(int i = 0; i < 8; i++) {
        xil_printf("%02x", data_byte[i]);
    }
    xil_printf("\r\n");

    for(int i = 0; i < 8; i++) {
        const u8 byte = data_byte[i];
        for(int j = 7; j >= 0; j--) {
            const u8 bit = (byte >> j) & 1;
            xil_printf("%d ", bit);
        }
        xil_printf("\r\n");
    }
    xil_printf("\r\n");
}