/*******************************************************************************
 * UserInterfaceCode.cpp – 12‑PWM Inverter UI (IO Outputs Only)
 *
 * Updated for new configuration:
 *   - Removed UART support and deadtime configuration.
 *   - Outputs now control:
 *       • Three phase enables (via two groups of outputs):
 *           - Visual feedback LEDs on PIN_LED_PHASE_A/B/C.
 *           - Dedicated phase selection outputs on PIN_PHASE_SEL_A/B/C.
 *       • Wave frequency select: only 50 or 60 Hz (via IO output).
 *       • Phase sequence select: 0 = ABC, 1 = ACB (via IO output).
 *       • Fan control: OFF (0) or ON (1) (via IO output).
 *
 * IO Outputs mapping:
 *   - Phase enable LED outputs (existing; for status/feedback):
 *       PIN_LED_PHASE_A (28), PIN_LED_PHASE_B (27), PIN_LED_PHASE_C (26)
 *   - Phase selection outputs:
 *       PIN_PHASE_SEL_A (20), PIN_PHASE_SEL_B (21), PIN_PHASE_SEL_C (22)
 *   - Wave frequency select: PIN_WAVE_FREQ_SELECT (7) – HIGH for 60 Hz, LOW for 50 Hz.
 *   - Phase sequence select: PIN_PHASE_SEQUENCE (8) – 0 = ABC, 1 = ACB.
 *   - Fan control: PIN_FAN_CTL (13) – 0 = OFF, 1 = ON.
 *
 * UI displays three pages (STATUS, CONFIG, FAULT). Adjustments update both
 * the status LEDs and the physical outputs.
 ******************************************************************************/

 #include <cstdio>
 #include <cstdlib>
 #include <cstring>
 #include <initializer_list>
 #include "pico/stdlib.h"
 #include "hardware/i2c.h"
 
 // -------------------- Pin Definitions --------------------
 
 // Buttons
 #define PIN_BTN_BACK      2
 #define PIN_BTN_FWD       3
 #define PIN_BTN_UP        4
 #define PIN_BTN_DOWN      5
 #define PIN_BTN_SEL       6
 
 // Status LEDs
 #define PIN_LED_NORMAL    10
 #define PIN_LED_FAULT     11
 #define PIN_LED_CONFIG    12
 
 // Phase enable status LEDs (for visual feedback)
 #define PIN_LED_PHASE_A   28
 #define PIN_LED_PHASE_B   27
 #define PIN_LED_PHASE_C   26
 
 // Fan indicator LEDs (optional, for status display)
 #define PIN_LED_FAN_L     1
 #define PIN_LED_FAN_M     0
 #define PIN_LED_FAN_H     9
 
 // New IO outputs for control signals:
 // Wave frequency select: HIGH for 60Hz, LOW for 50Hz.
 #define PIN_WAVE_FREQ_SELECT 21
 // Phase sequence select: 0 = ABC, 1 = ACB.
 #define PIN_PHASE_SEQUENCE   20
 // Fan control: HIGH means fan ON.
 #define PIN_FAN_CTL         19
 
 // New dedicated outputs for 3 phase selections.
 #define PIN_PHASE_SEL_A     18
 #define PIN_PHASE_SEL_B     17
 #define PIN_PHASE_SEL_C     16
 
 // I2C for LCD
 #define I2C_ID            i2c1
 #define I2C_SDA           14
 #define I2C_SCL           15
 #define I2C_BAUD          400000
 #define LCD_ADDR          0x27  // PCF8574 backpack
 
 // -------------------- Helper Functions --------------------
 
 // Button helper: returns true if the given pin is high.
 static inline bool btn_high(uint pin) {
     return (gpio_get(pin) == 1);
 }
 
 // Generic IO (or LED) helper: set a GPIO pin.
 static inline void io_set(uint pin, bool v) {
     gpio_put(pin, v);
 }
 
 // Update phase enable status LEDs (Phase A = bit0, B = bit1, C = bit2).
 static void update_phase_leds(uint8_t mask) {
     io_set(PIN_LED_PHASE_A, (mask & 0x01) ? true : false);
     io_set(PIN_LED_PHASE_B, (mask & 0x02) ? true : false);
     io_set(PIN_LED_PHASE_C, (mask & 0x04) ? true : false);
 }
 
 // Update dedicated phase selection outputs (Phase A = bit0, B = bit1, C = bit2).
 static void update_phase_selects(uint8_t mask) {
     io_set(PIN_PHASE_SEL_A, (mask & 0x01) ? true : false);
     io_set(PIN_PHASE_SEL_B, (mask & 0x02) ? true : false);
     io_set(PIN_PHASE_SEL_C, (mask & 0x04) ? true : false);
 }
 
 // Update fan indicator LEDs (for visual feedback).
 static void update_fan_leds(uint8_t m) {
     bool state = (m == 1);
     io_set(PIN_LED_FAN_L, state);
     io_set(PIN_LED_FAN_M, state);
     io_set(PIN_LED_FAN_H, state);
 }
 
 // Format fan mode string.
 static const char* fmt_fan(uint8_t m) {
     return (m == 1) ? "ON" : "OFF";
 }
 
 // Format phase string based on the phase enable mask.
 static void fmt_phase(char* out, uint8_t mask) {
     out[0] = (mask & 0x01) ? 'A' : '-';
     out[1] = (mask & 0x02) ? 'B' : '-';
     out[2] = (mask & 0x04) ? 'C' : '-';
     out[3] = '\0';
 }
 
 // -------------------- LCD Helper Functions --------------------
 namespace lcd {
     static inline void i2c_write(uint8_t d) {
         i2c_write_blocking(I2C_ID, LCD_ADDR, &d, 1, false);
     }
     static inline void pulse_en(uint8_t d) {
         i2c_write(d | 0x04); sleep_us(50);
         i2c_write(d & ~0x04); sleep_us(50);
     }
     static void write4(uint8_t nib, bool rs) {
         uint8_t data = 0x08 | (rs ? 0x01 : 0x00) | (nib << 4);
         i2c_write(data);
         pulse_en(data);
     }
     static void write8(uint8_t v, bool rs) {
         write4(v >> 4, rs);
         write4(v & 0x0F, rs);
     }
     static void cmd(uint8_t c) {
         write8(c, false);
         if(c < 4) sleep_ms(2);
     }
     static void data(uint8_t d) {
         write8(d, true);
     }
     static void init(){
         sleep_ms(50);
         write4(0x03, false); sleep_ms(5);
         write4(0x03, false); sleep_ms(5);
         write4(0x03, false); sleep_ms(5);
         write4(0x02, false); sleep_ms(5);
         cmd(0x28); cmd(0x0C); cmd(0x01); cmd(0x06);
     }
     static void clear(){
         cmd(0x01);
     }
     static void set_cursor(uint8_t c, uint8_t r) {
         cmd((r ? 0xC0 : 0x80) + c);
     }
     static void puts(const char* s) {
         while(*s) data(*s++);
     }
 }
 
 // -------------------- UI State and Configuration --------------------
 
 // UI Modes: STATUS, CONFIG, FAULT.
 enum UIMode   { MODE_STATUS, MODE_CONFIG, MODE_FAULT };
 // Configuration items: FREQ, PHASE, SEQ, FAN.
 enum ConfigIt { CONFIG_FREQ, CONFIG_PHASE, CONFIG_SEQ, CONFIG_FAN, CONFIG_COUNT };
 static const char* cfgNames[CONFIG_COUNT] = {"FREQ", "PHASE", "SEQ", "FAN"};
 
 // FanMode: OFF = 0, ON = 1.
 enum FanMode { FAN_OFF = 0, FAN_ON = 1 };
 
 static UIMode ui_mode = MODE_STATUS;
 static UIMode last_mode = MODE_STATUS;
 static uint8_t cfgIndex = 0;
 enum CfgSub   { CFG_BROWSE, CFG_ADJUST };
 static CfgSub cfg_sub = CFG_BROWSE;
 
 // Committed settings
 static uint16_t freq_hz   = 60;     // Only 50 or 60 Hz.
 static uint8_t  phase_msk = 0x07;   // Default: All three phases enabled.
 static uint8_t  phase_seq = 0;      // 0 = ABC, 1 = ACB.
 static FanMode  fan_mode  = FAN_OFF;
 
 // Temporary settings for editing
 static uint16_t t_freq;
 static uint8_t  t_phase;
 static uint8_t  t_seq;
 static bool     t_fan;
 
 // Fault and blink state
 static bool fault_flag = false;
 static char fault_msg[32] = "No Fault";
 static bool blink_on = true;
 static absolute_time_t next_blink = {0};
 
 // Phase cursor for CONFIG_PHASE (0 for Phase A, 1 for Phase B, 2 for Phase C)
 static uint8_t phase_cursor = 0;
 
 // -------------------- Update Outputs Function --------------------
 
 // Update all physical outputs based on the current committed settings.
 static void update_outputs() {
     // Update the status LEDs for phase enables.
     update_phase_leds(phase_msk);
     // Also update the dedicated phase selection outputs.
     update_phase_selects(phase_msk);
 
     // Wave frequency select output: HIGH for 60Hz, LOW for 50Hz.
     gpio_put(PIN_WAVE_FREQ_SELECT, (freq_hz == 60));
 
     // Phase sequence output: 0 = ABC, 1 = ACB.
     gpio_put(PIN_PHASE_SEQUENCE, phase_seq);
 
     // Fan control output: set HIGH if fan is ON.
     gpio_put(PIN_FAN_CTL, (fan_mode == FAN_ON));
 }
 
 // -------------------- UI Pages --------------------
 static void page_status(){
     lcd::clear();
     char l[17];
     sprintf(l, "FREQ=%uHz FAN=%s", freq_hz, (fan_mode == FAN_ON ? "ON" : "OFF"));
     lcd::puts(l);
     lcd::set_cursor(0,1);
     sprintf(l, "SEQ=%s", (phase_seq == 0 ? "ABC" : "ACB"));
     lcd::puts(l);
 }
 
 static void page_config(){
     lcd::clear();
     lcd::puts("CFG:");
     lcd::puts(cfgNames[cfgIndex]);
     char l[17] = {0};
     if(cfg_sub == CFG_ADJUST && !blink_on){
         strcpy(l, "     ");
     } else {
         switch(cfgIndex){
             case CONFIG_FREQ:
                 sprintf(l, "=%u", t_freq);
                 break;
             case CONFIG_PHASE: {
                 char ph[4];
                 fmt_phase(ph, t_phase);
                 sprintf(l, "=%s", ph);
                 break;
             }
             case CONFIG_SEQ:
                 sprintf(l, "=%s", (t_seq == 0 ? "ABC" : "ACB"));
                 break;
             case CONFIG_FAN:
                 sprintf(l, "=%s", t_fan ? "ON" : "OFF");
                 break;
             default:
                 break;
         }
     }
     lcd::set_cursor(9,0);
     lcd::puts(l);
     
     lcd::set_cursor(0,1);
     if(cfgIndex == CONFIG_PHASE && cfg_sub == CFG_ADJUST)
         lcd::puts("Up/Dn: Cycle; SEL: Toggle");
     else
         lcd::puts(cfg_sub == CFG_ADJUST ? "UP/DN adj  SEL save" : "SEL edit");
 }
 
 static void page_fault(){
     lcd::clear();
     lcd::puts("FAULT!");
     lcd::set_cursor(0,1);
     lcd::puts(fault_msg);
 }
 
 // -------------------- Commit Temporary Settings --------------------
 static void commit_temp_values(){
     freq_hz   = t_freq;
     phase_msk = t_phase;
     phase_seq = t_seq;
     fan_mode  = t_fan ? FAN_ON : FAN_OFF;
     update_outputs();
 }
 
 // -------------------- Button Handling --------------------
 static void handle_buttons(){
     // Page cycling when not in adjust mode.
     if(cfg_sub != CFG_ADJUST){
         if(btn_high(PIN_BTN_BACK)){
             ui_mode = (UIMode)(((int)ui_mode + 3 - 1) % 3);
             sleep_ms(200);
         }
         else if(btn_high(PIN_BTN_FWD)){
             ui_mode = (UIMode)(((int)ui_mode + 1) % 3);
             sleep_ms(200);
         }
     }
     
     static bool sel_prev = false;
     static absolute_time_t sel_down;
     
     if(ui_mode == MODE_CONFIG){
         if(cfg_sub == CFG_BROWSE){
             if(btn_high(PIN_BTN_UP)){
                 cfgIndex = (cfgIndex + CONFIG_COUNT - 1) % CONFIG_COUNT;
                 sleep_ms(150);
             }
             if(btn_high(PIN_BTN_DOWN)){
                 cfgIndex = (cfgIndex + 1) % CONFIG_COUNT;
                 sleep_ms(150);
             }
             if(btn_high(PIN_BTN_SEL)){
                 // Copy committed settings to temporary variables.
                 t_freq  = freq_hz;
                 t_phase = phase_msk;
                 t_seq   = phase_seq;
                 t_fan   = (fan_mode == FAN_ON);
                 phase_cursor = 0;
                 cfg_sub = CFG_ADJUST;
                 sleep_ms(200);
             }
         } else {  // CFG_ADJUST mode
             if(btn_high(PIN_BTN_BACK) || btn_high(PIN_BTN_FWD)){
                 commit_temp_values();
                 cfg_sub = CFG_BROWSE;
                 sleep_ms(200);
                 return;
             }
             switch(cfgIndex){
                 case CONFIG_FREQ:
                     if(btn_high(PIN_BTN_UP)){
                         t_freq = (t_freq == 50) ? 60 : 50;
                         sleep_ms(120);
                     }
                     if(btn_high(PIN_BTN_DOWN)){
                         t_freq = (t_freq == 60) ? 50 : 60;
                         sleep_ms(120);
                     }
                     break;
                 case CONFIG_PHASE:
                     // Use UP/DOWN to cycle through the phase bits.
                     if(btn_high(PIN_BTN_UP)){
                         phase_cursor = (phase_cursor + 1) % 3;
                         sleep_ms(120);
                     }
                     if(btn_high(PIN_BTN_DOWN)){
                         phase_cursor = (phase_cursor + 2) % 3;
                         sleep_ms(120);
                     }
                     // SEL toggles the corresponding phase bit.
                     if(btn_high(PIN_BTN_SEL) && !sel_prev){
                         sel_prev = true;
                         t_phase ^= (1 << phase_cursor);
                         sleep_ms(100);
                     } else if(!btn_high(PIN_BTN_SEL)){
                         sel_prev = false;
                     }
                     break;
                 case CONFIG_SEQ:
                     if(btn_high(PIN_BTN_UP) || btn_high(PIN_BTN_DOWN)){
                         t_seq ^= 1;
                         sleep_ms(120);
                     }
                     break;
                 case CONFIG_FAN:
                     if(btn_high(PIN_BTN_UP) || btn_high(PIN_BTN_DOWN)){
                         t_fan = !t_fan;
                         sleep_ms(120);
                     }
                     break;
                 default:
                     break;
             }
             static absolute_time_t sel_time;
             bool sel_now = btn_high(PIN_BTN_SEL);
             if(sel_now && !sel_prev){
                 sel_time = get_absolute_time();
             }
             if(!sel_now && sel_prev){
                 int held_ms = absolute_time_diff_us(sel_time, get_absolute_time()) / 1000;
                 if(held_ms >= 600){
                     commit_temp_values();
                     cfg_sub = CFG_BROWSE;
                 }
             }
             sel_prev = sel_now;
         }
     }
 }
 
 // -------------------- Main Function --------------------
 int main(){
     stdio_init_all();
 
     // Initialize button GPIO pins.
     uint pins_btn[] = {PIN_BTN_BACK, PIN_BTN_FWD, PIN_BTN_UP, PIN_BTN_DOWN, PIN_BTN_SEL};
     for(auto p : pins_btn) {
         gpio_init(p);
         gpio_set_dir(p, GPIO_IN);
     }
     
     // Initialize LED and IO output pins.
     // Includes status LEDs, phase enable LEDs, phase selection outputs,
     // and the new control outputs.
     uint pins_outputs[] = {
         PIN_LED_NORMAL, PIN_LED_FAULT, PIN_LED_CONFIG,
         PIN_LED_PHASE_A, PIN_LED_PHASE_B, PIN_LED_PHASE_C,
         PIN_PHASE_SEL_A, PIN_PHASE_SEL_B, PIN_PHASE_SEL_C,
         PIN_LED_FAN_L, PIN_LED_FAN_M, PIN_LED_FAN_H,
         PIN_WAVE_FREQ_SELECT, PIN_PHASE_SEQUENCE, PIN_FAN_CTL
     };
     for(auto p : pins_outputs) {
         gpio_init(p);
         gpio_set_dir(p, GPIO_OUT);
     }
     
     // Initialize I2C and LCD.
     i2c_init(I2C_ID, I2C_BAUD);
     gpio_set_function(I2C_SDA, GPIO_FUNC_I2C);
     gpio_set_function(I2C_SCL, GPIO_FUNC_I2C);
     lcd::init();
     lcd::puts("Pico UI online");
     sleep_ms(800);
     lcd::clear();
     
     // Initialize blink timer.
     next_blink = make_timeout_time_ms(250);
     
     // Output initial settings.
     update_outputs();
     
     while(true){
         handle_buttons();
         
         if(last_mode == MODE_CONFIG && ui_mode != MODE_CONFIG){
             if(cfg_sub == CFG_ADJUST){
                 commit_temp_values();
                 cfg_sub = CFG_BROWSE;
             }
         }
         last_mode = ui_mode;
         
         if(absolute_time_diff_us(get_absolute_time(), next_blink) <= 0){
             blink_on = !blink_on;
             next_blink = make_timeout_time_ms(250);
         }
         
         // Update status LEDs and dedicated phase selection outputs.
         update_phase_leds(phase_msk);
         update_phase_selects(phase_msk);
         update_fan_leds((ui_mode == MODE_CONFIG && cfg_sub == CFG_ADJUST)
                         ? (t_fan ? 1 : 0) : fan_mode);
                         
         // Normal LED: ON when not in CONFIG mode and no fault.
         gpio_put(PIN_LED_NORMAL, (ui_mode != MODE_CONFIG) && !fault_flag);
         gpio_put(PIN_LED_CONFIG, (ui_mode == MODE_CONFIG));
         gpio_put(PIN_LED_FAULT, fault_flag);
         
         // Draw the active page on the LCD.
         switch(ui_mode){
             case MODE_STATUS:
                 page_status();
                 break;
             case MODE_CONFIG:
                 page_config();
                 break;
             case MODE_FAULT:
                 page_fault();
                 break;
             default:
                 break;
         }
         
         sleep_ms(80);
     }
     
     return 0;
 }
 