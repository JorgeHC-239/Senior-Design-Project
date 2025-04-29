library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pwm_generator is
  port (
    clk     : in  std_logic;        -- 100 MHz clock
    rst     : in  std_logic;        -- active-high reset
    duty    : in  unsigned(7 downto 0); -- 8-bit duty: 0=0%, 255=~100%
    pwm_out : out std_logic         -- output at ~60 Hz
  );
end pwm_generator;

architecture Behavioral of pwm_generator is

  ----------------------------------------------------------------------------
  -- At 100 MHz, a single cycle is 10 ns. For a 60 Hz output, each period is:
  -- (1 / 60) s = ~16.666 ms => 16.666 ms / 10 ns = ~1,666,666.7 cycles.
  ----------------------------------------------------------------------------
  constant PERIOD_COUNT : integer := 1666667;  -- round to get ~60 Hz

  -- The counter runs from 0 to PERIOD_COUNT. Then we reset it to 0.
  signal counter   : integer range 0 to PERIOD_COUNT := 0;

  -- The threshold determines how many cycles are "HIGH". The ratio
  -- threshold / PERIOD_COUNT = duty / 256 => so duty=128 => ~50% 
  signal threshold : integer range 0 to PERIOD_COUNT := 0;

begin

  ----------------------------------------------------------------------------
  -- 1) Compute threshold from the 8-bit duty input.
  --    For duty=0, threshold=0 => 0% duty
  --    For duty=255 => threshold ~ PERIOD_COUNT => ~100% duty
  ----------------------------------------------------------------------------
  process(duty)
    variable duty_val : integer;
  begin
    duty_val := to_integer(duty); 
    threshold <= (duty_val * PERIOD_COUNT) / 256;  -- 256 = 2^8
  end process;

  ----------------------------------------------------------------------------
  -- 2) Increment counter each clock cycle, reset at PERIOD_COUNT
  ----------------------------------------------------------------------------
  process(clk, rst)
  begin
    if rst = '1' then
      counter <= 0;
    elsif rising_edge(clk) then
      if counter >= PERIOD_COUNT then
        counter <= 0;
      else
        counter <= counter + 1;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- 3) PWM output: HIGH if counter < threshold, else LOW
  ----------------------------------------------------------------------------
  pwm_out <= '1' when (counter < threshold) else '0';

end Behavioral;
