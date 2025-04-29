library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_rx is
  port(
    clk           : in  std_logic;                   -- 100 MHz clock
    rx            : in  std_logic;                   -- UART RX line
    rx_data       : out std_logic_vector(7 downto 0); -- captured byte
    rx_done_tick  : out std_logic                    -- pulses '1' for one clock on byte reception
  );
end uart_rx;

architecture Behavioral of uart_rx is

  ------------------------------------------------------------------
  -- For 100 MHz => 115,200 baud => ~868 cycles/bit
  ------------------------------------------------------------------
  constant CLKS_PER_BIT : integer := 868;

  type state_type is (IDLE, START, DATA, STOP);
  signal state_reg    : state_type := IDLE;

  signal clk_count    : integer range 0 to CLKS_PER_BIT-1 := 0;
  signal bit_index    : integer range 0 to 7 := 0;
  signal rx_shift_reg : std_logic_vector(7 downto 0) := (others => '0');

  signal rx_done_int  : std_logic := '0';
  signal rx_data_int  : std_logic_vector(7 downto 0) := (others => '0');

begin

  rx_data      <= rx_data_int;
  rx_done_tick <= rx_done_int;

  process(clk)
  begin
    if rising_edge(clk) then

      -- Default action: clear the rx_done_int pulse
      rx_done_int <= '0';

      case state_reg is

        -- IDLE: Wait for line to go low (start bit)
        when IDLE =>
          if rx = '0' then
            clk_count <= CLKS_PER_BIT / 2;  -- wait half a bit to sample center
            state_reg <= START;
          end if;

        -- START: after half-bit time, confirm still low
        when START =>
          if clk_count = 0 then
            if rx = '0' then
              bit_index <= 0;
              clk_count <= CLKS_PER_BIT - 1;
              state_reg <= DATA;
            else
              state_reg <= IDLE;
            end if;
          else
            clk_count <= clk_count - 1;
          end if;

        -- DATA: sample 8 bits at full-bit intervals
        when DATA =>
          if clk_count = 0 then
            rx_shift_reg(bit_index) <= rx;
            if bit_index = 7 then
              state_reg <= STOP;
            else
              bit_index <= bit_index + 1;
            end if;
            clk_count <= CLKS_PER_BIT - 1;
          else
            clk_count <= clk_count - 1;
          end if;

        -- STOP: wait 1 full bit time; line should return high
        when STOP =>
          if clk_count = 0 then
            rx_data_int <= rx_shift_reg;
            rx_done_int <= '1';  -- Produce a 1-clock pulse on completion
            state_reg   <= IDLE;
          else
            clk_count <= clk_count - 1;
          end if;

        when others =>
          state_reg <= IDLE;
      end case;
    end if;
  end process;

end Behavioral;
