library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_slave_top is
  port(
    clk            : in  std_logic;  -- e.g., 100MHz
    rst            : in  std_logic;  -- Active-low reset
    uart_rx        : in  std_logic;  -- RX line from external TX
    uart_tx        : out std_logic;  -- TX line to external RX

    reg_addr       : out std_logic_vector(3 downto 0);
    reg_wr_en      : out std_logic;
    reg_rd_en      : out std_logic;
    reg_wr_data    : out std_logic_vector(15 downto 0);
    reg_rd_data    : in  std_logic_vector(15 downto 0);
    reg_data_valid : in  std_logic
  );
end uart_slave_top;

architecture Behavioral of uart_slave_top is
    
  constant CLKS_PER_BIT : integer := 868;

  type state_type is (
      IDLE, CMD,
      WRITE_DATA1, WRITE_DATA2,
      PROCESS_WRITE, PROCESS_READ,
      SEND_READ1, SEND_READ2
  );
  signal state        : state_type := IDLE;
  
  signal rx_byte      : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_byte      : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_done      : std_logic := '0';
  signal tx_start     : std_logic := '0';
  signal tx_busy      : std_logic := '0';
  
  signal cmd_reg      : std_logic_vector(7 downto 0) := (others => '0');
  signal wr_data_reg  : std_logic_vector(15 downto 0) := (others => '0');
  signal addr_reg_int : std_logic_vector(3 downto 0) := (others => '0');

  -- Helper signal: bit7 of cmd_reg decides read/write (0=write, 1=read)
  signal rw_bit       : std_logic;

begin
  ----------------------------------------------------------------------------
  -- Instantiate UART Receiver
  --   rst => not rst => submodule sees active-high reset
  ----------------------------------------------------------------------------
  UART_RX_INST : entity work.uart_rx
    port map(
      clk           => clk,
      rst           => rst,
      rx            => uart_rx,
      rx_data       => rx_byte,
      rx_done_tick  => rx_done
    );

  ----------------------------------------------------------------------------
  -- Instantiate UART Transmitter
  --   rst => not rst => submodule sees active-high reset
  ----------------------------------------------------------------------------
  UART_TX_INST : entity work.uart_tx
    port map(
      clk       => clk,
      rst       => rst,
      tx_start  => tx_start,
      tx_data   => tx_byte,
      tx        => uart_tx,
      tx_busy   => tx_busy
    );

  ----------------------------------------------------------------------------
  -- Main State Machine
  ----------------------------------------------------------------------------
  process(clk, rst)
  begin
    if rst = '1' then
      state        <= IDLE;
      reg_wr_en    <= '0';
      reg_rd_en    <= '0';
      reg_addr     <= (others => '0');
      wr_data_reg  <= (others => '0');
      tx_start     <= '0';
      cmd_reg      <= (others => '0');
      rw_bit       <= '0';
      reg_wr_data  <= (others => '0');
    elsif rising_edge(clk) then
      -- Default signals each clock
      tx_start  <= '0';
      reg_wr_en <= '0';
      reg_rd_en <= '0';

      case state is

        ----------------------------------------------------------------------
        -- IDLE: Wait for first byte (the command byte)
        ----------------------------------------------------------------------
        when IDLE =>
          if rx_done = '1' then
            cmd_reg <= rx_byte;
            state   <= CMD;
          end if;

        ----------------------------------------------------------------------
        -- CMD: Extract read/write bit and address from the cmd_reg
        ----------------------------------------------------------------------
        when CMD =>
          rw_bit       <= cmd_reg(7);               -- bit7 = R/W
          addr_reg_int <= cmd_reg(3 downto 0);      -- bits3..0 = address
          reg_addr     <= cmd_reg(3 downto 0);

          if cmd_reg(7) = '0' then  -- Write command (R/W=0)
            state <= WRITE_DATA1;
          else                      -- Read command  (R/W=1)
            state <= PROCESS_READ;
          end if;

        ----------------------------------------------------------------------
        -- WRITE_DATA1: Wait for the MSB of the 16-bit data
        ----------------------------------------------------------------------
        when WRITE_DATA1 =>
          if rx_done = '1' then
            wr_data_reg(15 downto 8) <= rx_byte;
            state <= WRITE_DATA2;
          end if;

        ----------------------------------------------------------------------
        -- WRITE_DATA2: Wait for the LSB of the 16-bit data
        ----------------------------------------------------------------------
        when WRITE_DATA2 =>
          if rx_done = '1' then
            wr_data_reg(7 downto 0) <= rx_byte;
            state <= PROCESS_WRITE;
          end if;

        ----------------------------------------------------------------------
        -- PROCESS_WRITE: Assert reg_wr_en, pass the 16-bit data to the outside
        ----------------------------------------------------------------------
        when PROCESS_WRITE =>
          reg_wr_en   <= '1';
          reg_wr_data <= wr_data_reg;
          -- Return to IDLE (this completes the write transaction)
          state <= IDLE;

        ----------------------------------------------------------------------
        -- PROCESS_READ: Request the data from outside by asserting reg_rd_en
        ----------------------------------------------------------------------
        when PROCESS_READ =>
          reg_rd_en <= '1';
          -- Next, go wait for reg_data_valid in SEND_READ1
          state <= SEND_READ1;

        ----------------------------------------------------------------------
        -- SEND_READ1: Transmit the MSB of reg_rd_data
        ----------------------------------------------------------------------
        when SEND_READ1 =>
          if reg_data_valid = '1' then
            tx_byte  <= reg_rd_data(15 downto 8);  -- MSB
            tx_start <= '1';  -- one-cycle pulse to start TX
            state    <= SEND_READ2;
          end if;

        ----------------------------------------------------------------------
        -- SEND_READ2: After the MSB finishes, send the LSB
        ----------------------------------------------------------------------
        when SEND_READ2 =>
          -- Wait until TX is not busy
          if tx_busy = '0' then
            tx_byte  <= reg_rd_data(7 downto 0);   -- LSB
            tx_start <= '1';
            state    <= IDLE;
          end if;

        when others =>
          state <= IDLE;

      end case;
    end if;
  end process;

end Behavioral;
