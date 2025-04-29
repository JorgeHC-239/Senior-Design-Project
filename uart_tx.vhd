library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx is
  port(
    clk       : in  std_logic;                     -- 100 MHz clock
    rst       : in  std_logic;                     -- Active-high reset
    tx_start  : in  std_logic;                     -- 1-clock pulse to load tx_data
    tx_data   : in  std_logic_vector(7 downto 0);  -- data byte to send
    tx        : out std_logic;                     -- UART TX line
    tx_busy   : out std_logic                      -- '1' while sending a byte
  );
end uart_tx;

architecture FixedDownCount of uart_tx is

  ------------------------------------------------------------------
  -- For 100 MHz => 115,200 baud => ~868 cycles/bit
  ------------------------------------------------------------------
  constant CLKS_PER_BIT : integer := 868;

  type state_type is (IDLE, START, DATA, STOP);
  signal state_reg   : state_type := IDLE;
  signal clk_count   : integer range 0 to CLKS_PER_BIT-1 := 0;
  signal bit_index   : integer range 0 to 7 := 0;

  signal tx_reg      : std_logic := '1';  -- idle level = '1'
  signal tx_data_reg : std_logic_vector(7 downto 0) := (others => '0');
  signal busy_reg    : std_logic := '0';

begin

  tx      <= tx_reg;
  tx_busy <= busy_reg;

  process(clk)
  begin
    if rising_edge(clk) then

      if rst = '1' then
        -- Synchronous reset
        state_reg   <= IDLE;
        clk_count   <= 0;
        bit_index   <= 0;
        tx_reg      <= '1';  -- line idle
        tx_data_reg <= (others => '0');
        busy_reg    <= '0';

      else
        case state_reg is

          ----------------------------------------------------------------
          -- IDLE: Wait for tx_start pulse
          ----------------------------------------------------------------
          when IDLE =>
            tx_reg   <= '1';    -- line is idle-high
            busy_reg <= '0';
            if tx_start = '1' then
              tx_data_reg <= tx_data;   -- latch outgoing byte
              busy_reg    <= '1';
              state_reg   <= START;
              clk_count   <= CLKS_PER_BIT - 1;  -- preload a full bit period
            end if;

          ----------------------------------------------------------------
          -- START: Drive line low for 1 bit time
          ----------------------------------------------------------------
          when START =>
            tx_reg <= '0';  -- start bit
            if clk_count = 0 then
              -- one bit period elapsed
              state_reg   <= DATA;
              bit_index   <= 0;
              clk_count   <= CLKS_PER_BIT - 1;
            else
              clk_count <= clk_count - 1;
            end if;

          ----------------------------------------------------------------
          -- DATA: Send 8 data bits, LSB first
          ----------------------------------------------------------------
          when DATA =>
            tx_reg <= tx_data_reg(bit_index);
            if clk_count = 0 then
              if bit_index = 7 then
                state_reg <= STOP;
              else
                bit_index <= bit_index + 1;
              end if;
              clk_count <= CLKS_PER_BIT - 1;
            else
              clk_count <= clk_count - 1;
            end if;

          ----------------------------------------------------------------
          -- STOP: Drive line high for 1 bit time
          ----------------------------------------------------------------
          when STOP =>
            tx_reg <= '1';  -- stop bit
            if clk_count = 0 then
              busy_reg  <= '0';
              state_reg <= IDLE;
            else
              clk_count <= clk_count - 1;
            end if;

          when others =>
            state_reg <= IDLE;

        end case;
      end if;
    end if;
  end process;

end FixedDownCount;
