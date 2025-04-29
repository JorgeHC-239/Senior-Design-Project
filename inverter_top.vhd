library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.pwm_rom_pkg.all;

entity inverter_top is
   generic (
        PHASE_OFFSET_A : integer  := 0;
        PHASE_OFFSET_B : integer  := (PWM_LENGTH * 120) / 360;
        PHASE_OFFSET_C : integer  := (PWM_LENGTH * 240) / 360
    );
  port (
    clk100       : in std_logic;
    reset_btn    : in std_logic;
    
    -- Separate enable signals for each phase
    en_A         : in std_logic;
    en_B         : in std_logic;
    en_C         : in std_logic;
    
    -- Inputs for PWM sequencing (applied to each phase)
    wave_freq_hz : in std_logic_vector(15 downto 0);  -- in Hz (MSB justified)
    deadtime_ns  : in std_logic_vector(15 downto 0);  -- in nanoseconds
    
    -- 12 inverter output signals (4 per phase)
    Q1A, Q2A, Q3A, Q4A : out std_logic;
    Q1B, Q2B, Q3B, Q4B : out std_logic;
    Q1C, Q2C, Q3C, Q4C : out std_logic
  );
end inverter_top;

architecture Behavioral of inverter_top is
  signal pha_bus, phb_bus, phc_bus : std_logic_vector(3 downto 0);
begin
  phaseA : entity work.pwm_sequencer
    generic map (
      PHASE_OFFSET  => PHASE_OFFSET_A
     )
    port map (
      clk          => clk100,
      reset        => reset_btn,
      en           => en_A,
      wave_freq_hz => wave_freq_hz,
      deadtime_ns  => deadtime_ns,
      pwm          => pha_bus
    );

  phaseB : entity work.pwm_sequencer
    generic map (
      PHASE_OFFSET  => PHASE_OFFSET_B
     )
    port map (
      clk          => clk100,
      reset        => reset_btn,
      en           => en_B,
      wave_freq_hz => wave_freq_hz,
      deadtime_ns  => deadtime_ns,
      pwm          => phb_bus
    );

  phaseC : entity work.pwm_sequencer
    generic map (
      PHASE_OFFSET  => PHASE_OFFSET_C
     )
    port map (
      clk          => clk100,
      reset        => reset_btn,
      en           => en_C,
      wave_freq_hz => wave_freq_hz,
      deadtime_ns  => deadtime_ns,
      pwm          => phc_bus
    );

  Q1A <= pha_bus(0);  Q2A <= pha_bus(1);  Q3A <= pha_bus(2);  Q4A <= pha_bus(3);
  Q1B <= phb_bus(0);  Q2B <= phb_bus(1);  Q3B <= phb_bus(2);  Q4B <= phb_bus(3);
  Q1C <= phc_bus(0);  Q2C <= phc_bus(1);  Q3C <= phc_bus(2);  Q4C <= phc_bus(3);
  
end Behavioral;
