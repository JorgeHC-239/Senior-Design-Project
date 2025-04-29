library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fifo_8x8 is
    generic (
        DEPTH : integer := 16  -- Adjust this for a deeper FIFO if needed
    );
    port (
        clk      : in  std_logic;
        wr_en    : in  std_logic;
        rd_en    : in  std_logic;
        data_in  : in  std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0);
        empty    : out std_logic;
        full     : out std_logic
    );
end fifo_8x8;

architecture Behavioral of fifo_8x8 is

    -- Function to compute the ceiling of log2(n)
    function clog2(n: integer) return integer is
        variable i: integer := 0;
        variable j: integer := n - 1;
    begin
        while j > 0 loop
            j := j / 2;
            i := i + 1;
        end loop;
        return i;
    end function;

    constant PTR_WIDTH : integer := clog2(DEPTH);
    type mem_type is array (0 to DEPTH-1) of std_logic_vector(7 downto 0);
    signal mem    : mem_type := (others => (others => '0'));
    signal wr_ptr : unsigned(PTR_WIDTH-1 downto 0) := (others => '0');
    signal rd_ptr : unsigned(PTR_WIDTH-1 downto 0) := (others => '0');
    signal count  : unsigned(PTR_WIDTH downto 0) := (others => '0');

begin

    process(clk)
    begin
        if rising_edge(clk) then
            -- Write operation: if write enabled and FIFO is not full
            if (wr_en = '1' and count < DEPTH) then
                mem(to_integer(wr_ptr)) <= data_in;
                wr_ptr <= wr_ptr + 1;
                count <= count + 1;
            end if;
            -- Read operation: if read enabled and FIFO is not empty
            if (rd_en = '1' and count > 0) then
                rd_ptr <= rd_ptr + 1;
                count <= count - 1;
            end if;
        end if;
    end process;
    
    data_out <= mem(to_integer(rd_ptr));
    empty    <= '1' when count = 0 else '0';
    full     <= '1' when count = DEPTH else '0';

end Behavioral;
