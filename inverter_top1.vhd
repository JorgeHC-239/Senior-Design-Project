library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.pwm_rom_pkg.all;  -- Provides PWM_LENGTH, etc.

entity inverter_top is
  port(
    clk100  : in  std_logic;
    rst     : in  std_logic;  -- Although present at the top level, internal blocks no longer use it
    uart_rx : in  std_logic;  -- from Pico TX
    uart_tx : out std_logic;  -- to Pico RX (not used, tied to idle)
    
    -- Inverter outputs (12 signals)
    Q1A, Q2A, Q3A, Q4A : out std_logic;
    Q1B, Q2B, Q3B, Q4B : out std_logic;
    Q1C, Q2C, Q3C, Q4C : out std_logic;
    
    fan_out1 : out std_logic;
    fan_out2 : out std_logic
  );
end inverter_top;

architecture Behavioral of inverter_top is

  ------------------------------------------------------------------
  -- Inverter Setting Registers (default values)
  ------------------------------------------------------------------
  -- For reg_phase_en, we use 4 bits but only bits 2 downto 0 are used.
  signal reg_phase_en        : std_logic_vector(3 downto 0) := "0111";  -- Default: "0111" means bits 0-2 = "111"
  signal reg_wave_freq_sel   : std_logic := '0';  -- '0' = 50 Hz; '1' = 60 Hz
  signal reg_phase_order_sel : std_logic := '0';  -- '0' = ABC; '1' = ACB
  signal reg_deadtime        : std_logic_vector(15 downto 0) := x"00C8";  -- Default 200 ns (in hex)
  signal reg_fan_ctl         : std_logic := '0';  -- '0' = OFF; '1' = ON

  ------------------------------------------------------------------
  -- UART RX Signals and FIFO Signals
  ------------------------------------------------------------------
  signal rx_byte         : std_logic_vector(7 downto 0);
  signal rx_done         : std_logic;
  signal rx_wr_en        : std_logic := '0';

  signal rx_fifo_rd_en   : std_logic := '0';
  signal rx_fifo_dout    : std_logic_vector(7 downto 0);
  signal rx_fifo_empty   : std_logic;
  signal rx_fifo_full    : std_logic;

  ------------------------------------------------------------------
  -- Command Parser State Machine
  ------------------------------------------------------------------
  type parse_state_t is (IDLE, GOT_CMD, GOT_DATA1, GOT_DATA2);
  signal parser_state : parse_state_t := IDLE;
  signal cmd_reg      : std_logic_vector(7 downto 0) := (others => '0');
  signal data16       : std_logic_vector(15 downto 0) := (others => '0');

  ------------------------------------------------------------------
  -- Phase cursor for CONFIG_PHASE (if needed)
  ------------------------------------------------------------------
  signal phase_cursor : unsigned(1 downto 0) := (others => '0');
-- Declare an intermediate signal for FIFO output data
   signal fifo_data_reg : std_logic_vector(7 downto 0) := (others => '0');
  ------------------------------------------------------------------
  -- Inverter Core Instantiation
  ------------------------------------------------------------------
  component inverter_core is
    port(
      clk100          : in std_logic;
      rst             : in std_logic;
      phase_en        : in std_logic_vector(3 downto 0);
      wave_freq_select: in std_logic;
      phase_order_sel : in std_logic;
      deadtime_ns     : in std_logic_vector(15 downto 0);
      fan_ctl         : in std_logic;
      Q1A, Q2A, Q3A, Q4A : out std_logic;
      Q1B, Q2B, Q3B, Q4B : out std_logic;
      Q1C, Q2C, Q3C, Q4C : out std_logic;
      fan_out1        : out std_logic;
      fan_out2        : out std_logic
    );
  end component;

begin

  ------------------------------------------------------------------
  -- CORE_INST: Instantiate inverter_core.
  ------------------------------------------------------------------
  CORE_INST: entity work.inverter_core
    port map(
      clk100           => clk100,
      rst              => rst,  -- Passing the external reset without internal use in related processes.
      phase_en         => "0" & reg_phase_en(2 downto 0),  -- Pad MSB to get 4 bits
      wave_freq_select => reg_wave_freq_sel,
      phase_order_sel  => reg_phase_order_sel,
      deadtime_ns      => reg_deadtime,
      fan_ctl          => reg_fan_ctl,
      Q1A => Q1A, Q2A => Q2A, Q3A => Q3A, Q4A => Q4A,
      Q1B => Q1B, Q2B => Q2B, Q3B => Q3B, Q4B => Q4B,
      Q1C => Q1C, Q2C => Q2C, Q3C => Q3C, Q4C => Q4C,
      fan_out1 => fan_out1,
      fan_out2 => fan_out2
    );

  ------------------------------------------------------------------
  -- Tie UART TX line to idle, since we send no confirmations.
  ------------------------------------------------------------------
  uart_tx <= '1';

  ------------------------------------------------------------------
  -- UART_RX Instance
  ------------------------------------------------------------------
  U_RX: entity work.uart_rx
    port map(
      clk         => clk100,
      rx          => uart_rx,
      rx_data     => rx_byte,
      rx_done_tick=> rx_done
    );

  ------------------------------------------------------------------
  -- Process to write RX bytes into the RX FIFO (No reset branch)
  ------------------------------------------------------------------
  process(clk100)
  begin
    if rising_edge(clk100) then
      if (rx_done = '1' and rx_fifo_full = '0') then
        rx_wr_en <= '1';
      else
        rx_wr_en <= '0';
      end if;
    end if;
  end process;

  U_RX_FIFO: entity work.fifo_8x8
    generic map ( DEPTH => 16 )
    port map(
      clk      => clk100,
      wr_en    => rx_wr_en,
      rd_en    => rx_fifo_rd_en,
      data_in  => rx_byte,
      data_out => rx_fifo_dout,
      empty    => rx_fifo_empty,
      full     => rx_fifo_full
    );

  ------------------------------------------------------------------
  -- Command Parser Process (Reset removed)
  -- This process reads from the RX FIFO and decodes commands to update
  -- internal registers. No echo is produced.
  ------------------------------------------------------------------


process(clk100)
begin
  if rising_edge(clk100) then
    -- Default: deassert FIFO read enable every cycle.
    rx_fifo_rd_en <= '0';

    -- When we assert a read, latch the FIFO data.
    if rx_fifo_rd_en = '1' then
      fifo_data_reg <= rx_fifo_dout;
    end if;

    case parser_state is

      when IDLE =>
        if rx_fifo_empty = '0' then
          rx_fifo_rd_en <= '1';    -- Initiate read from FIFO.
          parser_state <= GOT_CMD;
        end if;

      when GOT_CMD =>
        cmd_reg <= fifo_data_reg;  -- Use the latched data.
        if fifo_data_reg(7) = '0' then  -- 3-byte command expected.
          parser_state <= GOT_DATA1;
        else  -- Toggle command.
          if fifo_data_reg(6) = '0' then
            reg_wave_freq_sel <= not reg_wave_freq_sel;
          else
            reg_phase_order_sel <= not reg_phase_order_sel;
          end if;
          parser_state <= IDLE;
        end if;

      when GOT_DATA1 =>
        if rx_fifo_empty = '0' then
          rx_fifo_rd_en <= '1';
          data16(15 downto 8) <= fifo_data_reg;
          parser_state <= GOT_DATA2;
        end if;

      when GOT_DATA2 =>
        if rx_fifo_empty = '0' then
          rx_fifo_rd_en <= '1';
          data16(7 downto 0) <= fifo_data_reg;
          parser_state <= IDLE;
          case cmd_reg(3 downto 0) is
            when "0000" =>
              reg_phase_en <= "0" & data16(2 downto 0);
            when "0001" =>
              reg_wave_freq_sel <= data16(0);
            when "0010" =>
              reg_deadtime <= data16;
            when "0011" =>
              reg_fan_ctl <= data16(0);
            when "0100" =>
              reg_phase_order_sel <= data16(0);
            when others =>
              null;
          end case;
        end if;

      when others =>
        parser_state <= IDLE;
    end case;
  end if;
end process;

end Behavioral;
