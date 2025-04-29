library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.pwm_rom_pkg.all;  -- Provides PWM_LENGTH, etc.

entity combined_inverter_xadc is
  port(
    clk100     : in  std_logic;
    rst        : in  std_logic;
    -- Inverter outputs
    Q1A, Q2A, Q3A, Q4A : out std_logic;
    Q1B, Q2B, Q3B, Q4B : out std_logic;
    Q1C, Q2C, Q3C, Q4C : out std_logic;
    -- Differential XADC analog inputs (passed through):
    vauxp0_sig  : in  std_logic;
    vauxn0_sig  : in  std_logic;
    vauxp1_sig  : in  std_logic;
    vauxn1_sig  : in  std_logic;
    vauxp2_sig  : in  std_logic;
    vauxn2_sig  : in  std_logic;
    vauxp9_sig  : in  std_logic;    -- VAUX9 (replaces previous VAUX3)
    vauxn9_sig  : in  std_logic;
    vauxp10_sig : in  std_logic;    -- VAUX10 (replaces previous VAUX4)
    vauxn10_sig : in  std_logic;
    -- Dynamic control inputs
    phase_en    : in  std_logic_vector(3 downto 0);
    wave_freq_hz: in  std_logic_vector(15 downto 0);  -- New: 16-bit vector input
    deadtime_ns : in  std_logic_vector(15 downto 0);  -- New: 16-bit vector input
    fan_ctl     : in  std_logic;
    -- XADC conversion outputs (16 bits each)
    xadc_data0  : out std_logic_vector(15 downto 0);
    xadc_data1  : out std_logic_vector(15 downto 0);
    xadc_data2  : out std_logic_vector(15 downto 0);
    xadc_data3  : out std_logic_vector(15 downto 0);
    xadc_data4  : out std_logic_vector(15 downto 0);
    -- (Optional) XADC PWM outputs - if you wish to drive external displays:
    xadc0_out   : out std_logic;
    xadc1_out   : out std_logic;
    xadc2_out   : out std_logic;
    xadc3_out   : out std_logic;
    xadc4_out   : out std_logic;
    -- Fan outputs (passed through)
    fan_out1    : out std_logic;
    fan_out2    : out std_logic
  );
end combined_inverter_xadc;

architecture Behavioral of combined_inverter_xadc is

  -- DRP interface signals for XADC Wizard instance.
  signal daddr_in_s : std_logic_vector(6 downto 0);
  signal den_in_s   : std_logic;
  signal dwe_in_s   : std_logic;
  signal di_in_s    : std_logic_vector(15 downto 0);
  signal do_out_s   : std_logic_vector(15 downto 0);
  signal drdy_out_s : std_logic;
  signal eoc_out_s  : std_logic;
  signal eos_out_s  : std_logic;

  -- Storage for conversion results from 5 channels.
  type xadc_array is array (0 to 4) of std_logic_vector(15 downto 0);
  signal xadc_data : xadc_array := (others => (others => '0'));
  
  -- DRP channel selection signals (mapping to VAUX channels).
  signal xadc_index : integer range 0 to 4 := 0;
  signal xadc_addr  : std_logic_vector(6 downto 0) := "0010000";
  
  -- Updated address map:
  -- Channel 0: VAUX0 (0x10 ? "0010000")
  -- Channel 1: VAUX1 (0x11 ? "0010001")
  -- Channel 2: VAUX2 (0x12 ? "0010010")
  -- Channel 3: VAUX9 (0x19 ? "0011001")
  -- Channel 4: VAUX10 (0x1A ? "0011010")
  type addr_array is array (0 to 4) of std_logic_vector(6 downto 0);
  constant XADC_ADDRS : addr_array := (
    0 => "0010000",
    1 => "0010001",
    2 => "0010010",
    3 => "0011001",
    4 => "0011010"
  );

   ----------------------------------------------------------------------------
  -- Duty cycle extraction signals (upper 8 bits of each XADC conversion result)
  ----------------------------------------------------------------------------
  signal duty0, duty1, duty2, duty3, duty4 : unsigned(7 downto 0) := (others => '0');
  
  
begin
  daddr_in_s <= xadc_addr;
  den_in_s   <= eoc_out_s;  -- Trigger new conversion on EOC.
  dwe_in_s   <= '0';
  di_in_s    <= (others => '0');
  
  -- Inverter instantiation.
  INV_INST: entity work.inverter_top
    generic map (
      PHASE_OFFSET_A => 0,
      PHASE_OFFSET_B => (PWM_LENGTH * 120) / 360,
      PHASE_OFFSET_C => (PWM_LENGTH * 240) / 360
    )
    port map(
      clk100    => clk100,
      reset_btn => not rst,
      en_A         => phase_en(0),
      en_B         => phase_en(1),
      en_C         => phase_en(2),
      wave_freq_hz => wave_freq_hz,
      deadtime_ns  => deadtime_ns,
      Q1A       => Q1A,
      Q2A       => Q2A,
      Q3A       => Q3A,
      Q4A       => Q4A,
      Q1B       => Q1B,
      Q2B       => Q2B,
      Q3B       => Q3B,
      Q4B       => Q4B,
      Q1C       => Q1C,
      Q2C       => Q2C,
      Q3C       => Q3C,
      Q4C       => Q4C
    );
  
  -- XADC Wizard instantiation.
  XADC_INST: entity work.xadc_wiz_0
    port map(
      dclk_in   => clk100,
      reset_in  => '0',
      daddr_in  => daddr_in_s,
      den_in    => den_in_s,
      dwe_in    => dwe_in_s,
      di_in     => di_in_s,
      do_out    => do_out_s,
      drdy_out  => drdy_out_s,

      vauxp0    => vauxp0_sig,
      vauxn0    => vauxn0_sig,
      vauxp1    => vauxp1_sig,
      vauxn1    => vauxn1_sig,
      vauxp2    => vauxp2_sig,
      vauxn2    => vauxn2_sig,
      vauxp9    => vauxp9_sig,   -- Map channel 3 to VAUX9.
      vauxn9    => vauxn9_sig,
      vauxp10    => vauxp10_sig,  -- Map channel 4 to VAUX10.
      vauxn10    => vauxn10_sig,

      vp_in     => '0',
      vn_in     => '0',

      eoc_out   => eoc_out_s,
      eos_out   => eos_out_s,
      alarm_out => open,
      user_temp_alarm_out => open,
      vccaux_alarm_out    => open,
      vccint_alarm_out    => open,
      ot_out    => open,
      busy_out  => open,
      channel_out => open
    );
  
  -- XADC Data Capture Process.
  process(clk100)
    variable next_index : integer;
  begin
    if rising_edge(clk100) then
      if rst = '0' then
        xadc_index <= 0;
        xadc_addr  <= XADC_ADDRS(0);
      elsif drdy_out_s = '1' then
        xadc_data(xadc_index) <= do_out_s;
        if xadc_index = 4 then
          next_index := 0;
        else
          next_index := xadc_index + 1;
        end if;
        xadc_index <= next_index;
        xadc_addr  <= XADC_ADDRS(next_index);
      end if;
    end if;
  end process;
  
  -- Output conversion data.
  xadc_data0 <= xadc_data(0);
  xadc_data1 <= xadc_data(1);
  xadc_data2 <= xadc_data(2);
  xadc_data3 <= xadc_data(3);
  xadc_data4 <= xadc_data(4);
  
  ----------------------------------------------------------------------------
  -- Duty Cycle Extraction:
  -- Extract the top 8 bits of each XADC conversion result.
  ----------------------------------------------------------------------------
  duty0 <= unsigned(xadc_data(0)(15 downto 8));
  duty1 <= unsigned(xadc_data(1)(15 downto 8));
  duty2 <= unsigned(xadc_data(2)(15 downto 8));
  duty3 <= unsigned(xadc_data(3)(15 downto 8));
  duty4 <= unsigned(xadc_data(4)(15 downto 8));
  
  ----------------------------------------------------------------------------
  -- PWM Generator Instantiations for Each XADC Channel:
  -- Use the provided pwm_generator component.
  ----------------------------------------------------------------------------
  pwm0: entity work.pwm_generator
    port map (
      clk     => clk100,
      rst     => not rst,  -- PWM generator uses active-low reset
      duty    => duty0,
      pwm_out => xadc0_out
    );
    
  pwm1: entity work.pwm_generator
    port map (
      clk     => clk100,
      rst     => not rst,
      duty    => duty1,
      pwm_out => xadc1_out
    );
    
  pwm2: entity work.pwm_generator
    port map (
      clk     => clk100,
      rst     => not rst,
      duty    => duty2,
      pwm_out => xadc2_out
    );
    
  pwm3: entity work.pwm_generator
    port map (
      clk     => clk100,
      rst     => not rst,
      duty    => duty3,
      pwm_out => xadc3_out
    );
    
  pwm4: entity work.pwm_generator
    port map (
      clk     => clk100,
      rst     => not rst,
      duty    => duty4,
      pwm_out => xadc4_out
    );
  
  -- Fan outputs are passed through from fan_ctl.
  fan_out1 <= fan_ctl;
  fan_out2 <= fan_ctl;
  
end Behavioral;
