library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.pwm_rom_pkg.all;  -- Provides PWM_LENGTH, etc.

------------------------------------------------------------------------------
-- inverter_core
--
-- Similar to your old inverter_top, but can dynamically switch between
-- ABC vs. ACB by setting phase_order_sel='0' or '1' at run-time,
-- and wave_freq_select='0' => 50Hz, '1' => 60Hz.
--
-- Dependencies:
--   - pwm_sequencer (modified to take phase_offset as a port instead of a generic)
------------------------------------------------------------------------------

entity inverter_core is
  port (
    clk100           : in  std_logic;
    rst              : in  std_logic;  -- active-high reset

    phase_en         : in  std_logic_vector(3 downto 0);
    wave_freq_select : in  std_logic;
    phase_order_sel  : in  std_logic;
    fan_ctl          : in  std_logic;
    -- 12 inverter outputs (4 per phase)
    Q1A, Q2A, Q3A, Q4A : out std_logic;
    Q1B, Q2B, Q3B, Q4B : out std_logic;
    Q1C, Q2C, Q3C, Q4C : out std_logic;
    
      -- Fan outputs (passed through)
    fan_out1    : out std_logic;
    fan_out2    : out std_logic
  );
end inverter_core;

architecture Behavioral of inverter_core is
   constant    deadtime_ns    :  std_logic_vector(15 downto 0) := x"0190";

  --------------------------------------------------------------------------
  -- We'll compute the offset for phases B, C at run-time based on
  -- phase_order_sel. If phase_order_sel='0' => ABC => B=120°, C=240°,
  -- if '1' => ACB => B=240°, C=120°.
  --------------------------------------------------------------------------
  signal offset_b_int : integer := (PWM_LENGTH * 120) / 360;
  signal offset_c_int : integer := (PWM_LENGTH * 240) / 360;

  --------------------------------------------------------------------------
  -- For wave_freq_select, we can store the actual freq in a 16-bit
  -- wave_freq_hz signal (50 or 60).
  --------------------------------------------------------------------------
  signal freq_reg : std_logic_vector(15 downto 0) := x"0032";  -- default 50

  --------------------------------------------------------------------------
  -- Intermediate bus signals from each pwm_sequencer (4 bits)
  --------------------------------------------------------------------------
  signal busA, busB, busC : std_logic_vector(3 downto 0);

begin

  --------------------------------------------------------------------------
  -- Process to set offset_b_int, offset_c_int, and freq_reg
  --------------------------------------------------------------------------
  process(clk100)
  begin
    if rising_edge(clk100) then
      if rst='1' then
        freq_reg <= x"0032";  -- default to 50
        offset_b_int <= (PWM_LENGTH*120)/360;
        offset_c_int <= (PWM_LENGTH*240)/360;
      else
        -- wave_freq_select => 0 => 50, 1 => 60
        if wave_freq_select='1' then
          freq_reg <= x"003C";  -- decimal 60
        else
          freq_reg <= x"0032";  -- decimal 50
        end if;

        if phase_order_sel='0' then
          -- ABC
          offset_b_int <= (PWM_LENGTH*120)/360;
          offset_c_int <= (PWM_LENGTH*240)/360;
        else
          -- ACB
          offset_b_int <= (PWM_LENGTH*240)/360;
          offset_c_int <= (PWM_LENGTH*120)/360;
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------------
  -- Phase A => offset=0
  --------------------------------------------------------------------------
  phaseA : entity work.pwm_sequencer
    port map(
      clk           => clk100,
      reset         => not rst,
      en            => phase_en(0),
      wave_freq_hz  => freq_reg,
      deadtime_ns   => deadtime_ns,
      phase_offset  => 0,
      pwm           => busA
    );

  --------------------------------------------------------------------------
  -- Phase B => offset_b_int
  --------------------------------------------------------------------------
  phaseB : entity work.pwm_sequencer
    port map(
      clk           => clk100,
      reset         => not rst,
      en            => phase_en(1),
      wave_freq_hz  => freq_reg,
      deadtime_ns   => deadtime_ns,
      phase_offset  => offset_b_int,
      pwm           => busB
    );

  --------------------------------------------------------------------------
  -- Phase C => offset_c_int
  --------------------------------------------------------------------------
  phaseC : entity work.pwm_sequencer
    port map(
      clk           => clk100,
      reset         => not rst,
      en            => phase_en(2),
      wave_freq_hz  => freq_reg,
      deadtime_ns   => deadtime_ns,
      phase_offset  => offset_c_int,
      pwm           => busC
    );

  --------------------------------------------------------------------------
  -- Map bus signals to Q outputs
  --------------------------------------------------------------------------
  Q1A <= busA(0);  Q2A <= busA(1);  Q3A <= busA(2);  Q4A <= busA(3);
  Q1B <= busB(0);  Q2B <= busB(1);  Q3B <= busB(2);  Q4B <= busB(3);
  Q1C <= busC(0);  Q2C <= busC(1);  Q3C <= busC(2);  Q4C <= busC(3);

 -- Fan outputs are passed through from fan_ctl.
  fan_out1 <= fan_ctl;
  fan_out2 <= fan_ctl;
  
end Behavioral;
