library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.pwm_rom_pkg.all;  -- This package provides PWM_LENGTH and PWM_ROM

entity pwm_sequencer is
    generic (
        PHASE_OFFSET  : integer  := 0
    );
  port (
    clk         : in  std_logic;
    reset       : in  std_logic;  -- Active-HIGH reset
    en          : in  std_logic;  -- Enable for this PWM channel
    wave_freq_hz: in  std_logic_vector(15 downto 0);  -- New: 16-bit vector input
    deadtime_ns : in  std_logic_vector(15 downto 0);  -- New: 16-bit vector input
    pwm         : out std_logic_vector(3 downto 0)
  );
end pwm_sequencer;

architecture Behavioral of pwm_sequencer is

  constant CLOCK_FREQ_HZ : positive := 100_000_000;
  
  -- Function to get maximum value.
  function max_pos(a, b : positive) return positive is
  begin
    if a > b then return a; else return b; end if;
  end function;
  
  ----------------------------------------------------------------------------
  -- Local signals to hold the converted integer values.
  ----------------------------------------------------------------------------
  signal local_wave_freq : integer := 60;
  signal local_deadtime  : integer := 200;
  
  ----------------------------------------------------------------------------
  -- Parameters for PWM generation.
  ----------------------------------------------------------------------------
  signal ticks_per_sample : positive := 1;
  signal deadtime_cyc     : positive := 1;
  signal DT_CYC           : positive := 1;
  
  signal tick_cnt         : unsigned(31 downto 0) := (others => '0');
  signal rom_idx          : integer range 0 to PWM_LENGTH-1 := 0;
  signal desired          : std_logic_vector(3 downto 0);
  signal pwm_reg          : std_logic_vector(3 downto 0) := (others => '0');
  
  type dt_arr is array (3 downto 0) of integer range 0 to 1024;
  signal dt_cnt           : dt_arr := (others => 0);
  
begin

  ----------------------------------------------------------------------------
  -- Parameter Calculation Process
  ----------------------------------------------------------------------------
  param_calc: process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        local_wave_freq <= 60;
        local_deadtime  <= 200;
        ticks_per_sample <= 1;
        deadtime_cyc <= 1;
        DT_CYC <= 1;
      else
        -- Convert incoming 16-bit vector inputs to integer.
        local_wave_freq <= to_integer(unsigned(wave_freq_hz));
        local_deadtime  <= to_integer(unsigned(deadtime_ns));
        ticks_per_sample <= (CLOCK_FREQ_HZ + (local_wave_freq * PWM_LENGTH)/2) / (local_wave_freq * PWM_LENGTH);
        deadtime_cyc <= (CLOCK_FREQ_HZ * local_deadtime + 500000000) / 1000000000;
        if deadtime_cyc < 1 then
          DT_CYC <= 1;
        else
          DT_CYC <= deadtime_cyc;
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Sample-rate generator: Step through the PWM ROM at the rate determined by ticks_per_sample.
  ----------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        tick_cnt <= (others => '0');
        rom_idx  <= 0;
      elsif tick_cnt = to_unsigned(ticks_per_sample - 1, tick_cnt'length) then
        tick_cnt <= (others => '0');
        if rom_idx = PWM_LENGTH - 1 then
          rom_idx <= 0;
        else
          rom_idx <= rom_idx + 1;
        end if;
      else
        tick_cnt <= tick_cnt + 1;
      end if;
    end if;
  end process;
  
    desired <= PWM_ROM((rom_idx + PHASE_OFFSET) mod PWM_LENGTH);
  
  ----------------------------------------------------------------------------
  -- Dead-time insertion and PWM output update.
  ----------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        pwm_reg <= (others => '0');
        dt_cnt  <= (others => 0);
      elsif en = '0' then
        pwm_reg <= (others => '0');
        dt_cnt  <= (others => 0);
      else
        for i in 0 to 3 loop
          if desired(i) = '1' then  -- channel should go high
            if pwm_reg(i) = '0' then  -- detect rising edge, insert dead-time
              if dt_cnt(i) < integer(DT_CYC) then
                dt_cnt(i) <= dt_cnt(i) + 1;
              else
                pwm_reg(i) <= '1';
                dt_cnt(i) <= 0;
              end if;
            else
              dt_cnt(i) <= 0;
            end if;
          else  -- channel should be low
            pwm_reg(i) <= '0';
            dt_cnt(i) <= 0;
          end if;
        end loop;
      end if;
    end if;
  end process;

  pwm <= pwm_reg;

end Behavioral;
