library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity combined_inverter_xadc_uart is
  port (
    clk100    : in  std_logic;      -- 100 MHz clock
    rst       : in  std_logic;      -- Possibly active-low externally

    -- UART signals
    uart_rx   : in  std_logic;      -- from Pico TX
    uart_tx   : out std_logic;      -- to Pico RX

    -- Inverter outputs
    Q1A, Q2A, Q3A, Q4A : out std_logic;
    Q1B, Q2B, Q3B, Q4B : out std_logic;
    Q1C, Q2C, Q3C, Q4C : out std_logic;

    -- XADC analog inputs
    vauxp0_sig, vauxn0_sig : in  std_logic;
    vauxp1_sig, vauxn1_sig : in  std_logic;
    vauxp2_sig, vauxn2_sig : in  std_logic;
    vauxp9_sig, vauxn9_sig : in  std_logic;
    vauxp10_sig, vauxn10_sig : in  std_logic;

    -- Fan outputs
    fan_out1, fan_out2 : out std_logic;

    -- XADC PWM outputs
    xadc0_out, xadc1_out, xadc2_out, xadc3_out, xadc4_out : out std_logic
  );
end combined_inverter_xadc_uart;

architecture Behavioral of combined_inverter_xadc_uart is

  ------------------------------------------------------------------
  -- For 100 MHz -> 115,200 baud => ~868 cycles
  ------------------------------------------------------------------
  constant CLKS_PER_BIT : integer := 868;

  ------------------------------------------------------------------
  -- Submodule: combined_inverter_xadc
  ------------------------------------------------------------------
  component combined_inverter_xadc is
    port(
      clk100     : in  std_logic;
      rst        : in  std_logic;
      Q1A, Q2A, Q3A, Q4A : out std_logic;
      Q1B, Q2B, Q3B, Q4B : out std_logic;
      Q1C, Q2C, Q3C, Q4C : out std_logic;
      vauxp0_sig, vauxn0_sig,
      vauxp1_sig, vauxn1_sig,
      vauxp2_sig, vauxn2_sig,
      vauxp9_sig, vauxn9_sig,
      vauxp10_sig, vauxn10_sig : in std_logic;

      phase_en    : in std_logic_vector(3 downto 0);
      wave_freq_hz: in unsigned(15 downto 0);
      deadtime_ns : in unsigned(15 downto 0);
      fan_ctl     : in std_logic;

      xadc_data0, xadc_data1, xadc_data2, xadc_data3, xadc_data4 : out std_logic_vector(15 downto 0);
      xadc0_out, xadc1_out, xadc2_out, xadc3_out, xadc4_out : out std_logic;
      fan_out1, fan_out2 : out std_logic
    );
  end component;

  ------------------------------------------------------------------
  -- Submodules: uart_rx, uart_tx, and FIFO
  -----------------------------------------------------------------

  component fifo_8x8 is
    generic(
      DEPTH : integer := 16
    );
    port(
      clk      : in  std_logic;
      rst      : in  std_logic;  -- active-high
      wr_en    : in  std_logic;
      rd_en    : in  std_logic;
      data_in  : in  std_logic_vector(7 downto 0);
      data_out : out std_logic_vector(7 downto 0);
      empty    : out std_logic;
      full     : out std_logic
    );
  end component;

  ------------------------------------------------------------------
  -- Signals for your dynamic registers
  ------------------------------------------------------------------
  signal reg_phase_en  : std_logic_vector(3 downto 0) := "0000";
  signal reg_wave_freq : std_logic_vector(15 downto 0) := x"003C";
  signal reg_deadtime  : std_logic_vector(15 downto 0) := x"00C8";
  signal reg_fan_ctl   : std_logic := '1';

  ------------------------------------------------------------------
  -- XADC data
  ------------------------------------------------------------------
  signal reg_xadc0, reg_xadc1, reg_xadc2, reg_xadc3, reg_xadc4 : std_logic_vector(15 downto 0) := (others => '0');

  -- pass to submodule
  signal phase_en_sig   : std_logic_vector(3 downto 0);
  signal wave_freq_sig  : unsigned(15 downto 0);
  signal deadtime_sig   : unsigned(15 downto 0);
  signal fan_ctl_sig    : std_logic;

  -- from submodule
  signal xadc_data0, xadc_data1, xadc_data2, xadc_data3, xadc_data4 : std_logic_vector(15 downto 0);

  ------------------------------------------------------------------
  -- UART RX side signals
  ------------------------------------------------------------------
  signal rx_byte     : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_done     : std_logic := '0';

  ------------------------------------------------------------------
  -- RX FIFO signals
  ------------------------------------------------------------------
  signal rx_fifo_wr_en   : std_logic := '0';
  signal rx_fifo_rd_en   : std_logic := '0';
  signal rx_fifo_dout    : std_logic_vector(7 downto 0);
  signal rx_fifo_empty   : std_logic;
  signal rx_fifo_full    : std_logic;

  ------------------------------------------------------------------
  -- TX FIFO signals
  ------------------------------------------------------------------
  signal tx_fifo_wr_en   : std_logic := '0';
  signal tx_fifo_rd_en   : std_logic := '0';
  signal tx_fifo_din     : std_logic_vector(7 downto 0);
  signal tx_fifo_dout    : std_logic_vector(7 downto 0);
  signal tx_fifo_empty   : std_logic;
  signal tx_fifo_full    : std_logic;

  ------------------------------------------------------------------
  -- UART TX side signals
  ------------------------------------------------------------------
  signal tx_start_sig  : std_logic := '0';
  signal tx_busy_sig   : std_logic := '0';

  ------------------------------------------------------------------
  -- Command parser signals
  ------------------------------------------------------------------
  type state_type is (IDLE, CMD, WRITE_D1, WRITE_D2, WRITE_PROC, READ_PROC, SEND_HI, SEND_LO);
  signal state_reg : state_type := IDLE;

  signal cmd_reg   : std_logic_vector(7 downto 0) := (others => '0');
  signal data_reg  : std_logic_vector(15 downto 0) := (others => '0');

begin
  ------------------------------------------------------------------
  -- Inst combined_inverter_xadc
  ------------------------------------------------------------------
  XADC_INV: combined_inverter_xadc
    port map(
      clk100 => clk100,
      rst    => rst,  -- if submodule is also active-high
      Q1A=>Q1A, Q2A=>Q2A, Q3A=>Q3A, Q4A=>Q4A,
      Q1B=>Q1B, Q2B=>Q2B, Q3B=>Q3B, Q4B=>Q4B,
      Q1C=>Q1C, Q2C=>Q2C, Q3C=>Q3C, Q4C=>Q4C,
      vauxp0_sig => vauxp0_sig,
      vauxn0_sig => vauxn0_sig,
      vauxp1_sig => vauxp1_sig,
      vauxn1_sig => vauxn1_sig,
      vauxp2_sig => vauxp2_sig,
      vauxn2_sig => vauxn2_sig,
      vauxp9_sig => vauxp9_sig,
      vauxn9_sig => vauxn9_sig,
      vauxp10_sig=> vauxp10_sig,
      vauxn10_sig=> vauxn10_sig,
      phase_en   => phase_en_sig,
      wave_freq_hz=> wave_freq_sig,
      deadtime_ns => deadtime_sig,
      fan_ctl    => fan_ctl_sig,
      xadc_data0 => xadc_data0,
      xadc_data1 => xadc_data1,
      xadc_data2 => xadc_data2,
      xadc_data3 => xadc_data3,
      xadc_data4 => xadc_data4,
      xadc0_out  => xadc0_out,
      xadc1_out  => xadc1_out,
      xadc2_out  => xadc2_out,
      xadc3_out  => xadc3_out,
      xadc4_out  => xadc4_out,
      fan_out1   => fan_out1,
      fan_out2   => fan_out2
    );

  ------------------------------------------------------------------
  -- Latch or pass-through XADC data into local regs if desired
  ------------------------------------------------------------------
  reg_xadc0 <= xadc_data0;
  reg_xadc1 <= xadc_data1;
  reg_xadc2 <= xadc_data2;
  reg_xadc3 <= xadc_data3;
  reg_xadc4 <= xadc_data4;

  phase_en_sig  <= reg_phase_en;
  wave_freq_sig <= unsigned(reg_wave_freq);
  deadtime_sig  <= unsigned(reg_deadtime);
  fan_ctl_sig   <= reg_fan_ctl;

  ------------------------------------------------------------------
  -- Instantiate RX, TX
  -- We assume they require active-high reset => pass 'rst => not rst' if your top-level is active-low
  ------------------------------------------------------------------
  U_RX : entity work.uart_rx
    port map(
      clk          => clk100,
      rst          => not rst,  -- submodule sees active-high
      rx           => uart_rx,
      rx_data      => rx_byte,
      rx_done_tick => rx_done
    );

  U_TX : entity work.uart_tx
    port map(
      clk       => clk100,
      rst       => not rst,
      tx_start  => tx_start_sig,
      tx_data   => tx_fifo_dout,
      tx        => uart_tx,
      tx_busy   => tx_busy_sig
    );

  ------------------------------------------------------------------
  -- Inbound FIFO (rx_fifo)
  ------------------------------------------------------------------
  U_RX_FIFO : entity work.fifo_8x8
    generic map(DEPTH=>16)
    port map(
      clk      => clk100,
      rst      => not rst,       -- active-high
      wr_en    => rx_fifo_wr_en,
      rd_en    => rx_fifo_rd_en,
      data_in  => rx_byte,
      data_out => rx_fifo_dout,
      empty    => rx_fifo_empty,
      full     => rx_fifo_full
    );

  -- Write inbound bytes to rx_fifo
  process(clk100)
  begin
    if rising_edge(clk100) then
      if rst = '0' then
        rx_fifo_wr_en <= '0';
      else
        if (rx_done='1' and rx_fifo_full='0') then
          rx_fifo_wr_en <= '1';
        else
          rx_fifo_wr_en <= '0';
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------
  -- Outbound FIFO (tx_fifo)
  ------------------------------------------------------------------
  U_TX_FIFO : entity work.fifo_8x8
    generic map(DEPTH=>16)
    port map(
      clk      => clk100,
      rst      => not rst,
      wr_en    => tx_fifo_wr_en,
      rd_en    => tx_fifo_rd_en,
      data_in  => tx_fifo_din,   -- from parser
      data_out => tx_fifo_dout,
      empty    => tx_fifo_empty,
      full     => tx_fifo_full
    );

  ------------------------------------------------------------------
  -- Draining the tx_fifo to the transmitter
  -- If TX not busy, and not empty, we read next byte, do tx_start.
  ------------------------------------------------------------------
  process(clk100)
  begin
    if rising_edge(clk100) then
      if rst='0' then
        tx_start_sig   <= '0';
        tx_fifo_rd_en  <= '0';
      else
        -- default
        tx_start_sig  <= '0';
        tx_fifo_rd_en <= '0';

        if (tx_busy_sig='0') and (tx_fifo_empty='0') then
          tx_fifo_rd_en <= '1';
          tx_start_sig  <= '1';
          -- on next clock, that read data is in tx_fifo_dout -> goes to tx_data
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------
  -- Command Parser using inbound FIFO data
  -- 1) read a command byte from rx_fifo
  -- 2) if write, read next 2 bytes => do reg write
  -- 3) if read, push 2 response bytes into tx_fifo
  ------------------------------------------------------------------
  process(clk100)
  begin
    if rising_edge(clk100) then
      if rst='0' then
        state_reg    <= IDLE;
        rx_fifo_rd_en<= '0';
        cmd_reg      <= (others => '0');
        data_reg     <= (others => '0');
        -- defaults
        reg_phase_en <= "0000";
        reg_wave_freq<= x"003C";
        reg_deadtime <= x"00C8";
        reg_fan_ctl  <= '1';
        tx_fifo_wr_en<= '0';
        tx_fifo_din  <= (others => '0');

      else
        -- default signals
        rx_fifo_rd_en <= '0';
        tx_fifo_wr_en <= '0';

        case state_reg is
          when IDLE =>
            if (rx_fifo_empty='0') then
              rx_fifo_rd_en <= '1';    -- read one byte from inbound FIFO
              state_reg     <= CMD;
            end if;

          when CMD =>
            cmd_reg   <= rx_fifo_dout;
            -- parse bit7 => read or write
            if rx_fifo_dout(7)='0' then
              -- write cmd => next 2 bytes are data
              state_reg <= WRITE_D1;
            else
              -- read => we will eventually enqueue 2 reply bytes
              state_reg <= READ_PROC;
            end if;

          when WRITE_D1 =>
            if (rx_fifo_empty='0') then
              rx_fifo_rd_en <= '1';
              data_reg(15 downto 8) <= rx_fifo_dout;
              state_reg <= WRITE_D2;
            end if;

          when WRITE_D2 =>
            if (rx_fifo_empty='0') then
              rx_fifo_rd_en <= '1';
              data_reg(7 downto 0) <= rx_fifo_dout;
              state_reg <= WRITE_PROC;
            end if;

          when WRITE_PROC =>
            -- lower nibble of cmd_reg => address
            case cmd_reg(3 downto 0) is
              when "0000" => reg_phase_en <= data_reg(3 downto 0);
              when "0001" => reg_wave_freq<= data_reg;
              when "0010" => reg_deadtime <= data_reg;
              when "0011" => reg_fan_ctl  <= data_reg(0);
              when others => null;
            end case;
            state_reg <= IDLE;  -- done

          when READ_PROC =>
            -- read => lower nibble => which address?
            case cmd_reg(3 downto 0) is
              when "0000" =>
                data_reg <= (11 downto 0 => '0') & reg_phase_en;
              when "0001" =>
                data_reg <= reg_wave_freq;
              when "0010" =>
                data_reg <= reg_deadtime;
              when "0011" =>
                data_reg <= (15 downto 1 => '0') & reg_fan_ctl;
              when "0100" =>
                data_reg <= reg_xadc0;
              when "0101" =>
                data_reg <= reg_xadc1;
              when "0110" =>
                data_reg <= reg_xadc2;
              when "0111" =>
                data_reg <= reg_xadc3;
              when "1000" =>
                data_reg <= reg_xadc4;
              when others =>
                data_reg <= (others => '0');
            end case;
            state_reg <= SEND_HI;

          when SEND_HI =>
            -- send high byte
            if tx_fifo_full='0' then
              tx_fifo_din <= data_reg(15 downto 8);
              tx_fifo_wr_en <= '1';
              state_reg <= SEND_LO;
            end if;

          when SEND_LO =>
            -- send low byte
            if tx_fifo_full='0' then
              tx_fifo_din <= data_reg(7 downto 0);
              tx_fifo_wr_en <= '1';
              state_reg <= IDLE;
            end if;

          when others =>
            state_reg <= IDLE;
        end case;
      end if;  -- rst else
    end if;  -- rising edge
  end process;

end Behavioral;
