library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_echo_fifo is
  port (
    clk100   : in  std_logic;  -- 100 MHz clock
    rst      : in  std_logic;  -- active-high reset (external)
    uart_rx  : in  std_logic;  -- from external TX
    uart_tx  : out std_logic   -- to external RX
  );
end entity;

architecture Behavioral of top_echo_fifo is

  ------------------------------------------------------------------
  -- Signals for the UART RX/TX modules
  ------------------------------------------------------------------
  signal rx_byte     : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_done     : std_logic := '0';
  signal tx_start    : std_logic := '0';
  signal tx_busy     : std_logic := '0';
  signal tx_data_reg : std_logic_vector(7 downto 0) := (others => '0');

  ------------------------------------------------------------------
  -- FIFO signals
  ------------------------------------------------------------------
  signal fifo_data_out : std_logic_vector(7 downto 0);
  signal fifo_empty    : std_logic;
  signal fifo_full     : std_logic;
  signal fifo_wr_en    : std_logic := '0';
  signal fifo_rd_en    : std_logic := '0';

begin

  ------------------------------------------------------------------
  -- Instantiate UART Receiver (rx module)
  --
  -- Note that the reset is inverted for the RX module.
  ------------------------------------------------------------------
  U_RX: entity work.uart_rx
    port map(
      clk          => clk100,
      rst          => not rst,     -- Inverted reset for submodules
      rx           => uart_rx,
      rx_data      => rx_byte,
      rx_done_tick => rx_done
    );

  ------------------------------------------------------------------
  -- Instantiate UART Transmitter (tx module)
  --
  -- Again, the reset is inverted.
  ------------------------------------------------------------------
  U_TX: entity work.uart_tx
    port map(
      clk       => clk100,
      rst       => not rst,
      tx_start  => tx_start,
      tx_data   => tx_data_reg,
      tx        => uart_tx,
      tx_busy   => tx_busy
    );

  ------------------------------------------------------------------
  -- Instantiate FIFO to buffer received bytes
  ------------------------------------------------------------------
  U_FIFO: entity work.fifo_8x8
    generic map (
      DEPTH => 16
    )
    port map (
      clk      => clk100,
      rst      => not rst,   -- Use external reset (active-high)
      wr_en    => fifo_wr_en,
      rd_en    => fifo_rd_en,
      data_in  => rx_byte,
      data_out => fifo_data_out,
      empty    => fifo_empty,
      full     => fifo_full
    );

  ------------------------------------------------------------------
  -- Process to write received bytes into the FIFO.
  --
  -- When rx_done is high, and if the FIFO is not full, we assert
  -- fifo_wr_en to enqueue the received data.
  ------------------------------------------------------------------
  process(clk100)
  begin
    if rising_edge(clk100) then
      if rst = '0' then
        fifo_wr_en <= '0';
      else
        if rx_done = '1' and fifo_full = '0' then
          fifo_wr_en <= '1';
        else
          fifo_wr_en <= '0';
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------
  -- Process to read from the FIFO and send data through the TX.
  --
  -- If TX is idle and the FIFO is not empty then load tx_data_reg
  -- with the next available byte, assert tx_start for one clock cycle,
  -- and dequeue the FIFO by asserting fifo_rd_en.
  ------------------------------------------------------------------
  process(clk100)
  begin
    if rising_edge(clk100) then
      if rst = '0' then
        tx_start   <= '0';
        fifo_rd_en <= '0';
        tx_data_reg <= (others => '0');
      else
        -- Default: deassert control signals
        tx_start   <= '0';
        fifo_rd_en <= '0';
        
        if (tx_busy = '0') and (fifo_empty = '0') then
          -- Load the next byte from the FIFO into TX,
          -- and signal the transmitter to start.
          tx_data_reg <= fifo_data_out;
          tx_start    <= '1';   -- one-clock pulse to start transmission
          fifo_rd_en  <= '1';   -- dequeue the FIFO
        end if;
      end if;
    end if;
  end process;

end Behavioral;
