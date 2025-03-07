-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Kryštof Paulík <xpauli08 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

  -- CNT
  signal cnt_val  : std_logic_vector (12 downto 0);
  signal cnt_inc  : std_logic;
  signal cnt_dec  : std_logic;
  signal cnt_one  : std_logic;

  -- PC
  signal pc_val  : std_logic_vector (11 downto 0);
  signal pc_inc  : std_logic;
  signal pc_dec  : std_logic;

  -- PTR
  signal ptr_val  : std_logic_vector (11 downto 0);
  signal ptr_inc  : std_logic;
  signal ptr_dec  : std_logic;

  -- MUX1
  signal mux1_select : std_logic := '0';
  signal mux1_out    : std_logic_vector (12 downto 0) := (others => '0');

  -- MUX2
  signal mux2_select : std_logic_vector (1 downto 0) := (others => '0');
  signal mux2_out    : std_logic_vector (7 downto 0) := (others => '0');

  -- FSM
  type fsm_state is (
    s_fetch,
    s_decode,
    s_init,
    -- PTR
    s_ptr_inc,
    s_ptr_dec,
    -- ADDR VALUE
    s_val_inc,
    s_val_load_inc,
    s_val_end_inc,

    s_val_dec,
    s_val_load_dec,
    s_val_end_dec,
    -- WHILE START
    s_wh_start,
    s_wh_start2,
    s_wh_start3,
    s_wh_start4,
    s_wh_start_wait,
    s_wh_start_wait2,
    s_wh_start_wait3,
    s_wh_start_wait4,
    -- WHILE END
    s_wh_end,
    s_wh_end2,
    s_wh_end3,
    s_wh_end4,
    s_wh_end5,
    s_wh_end_wait,
    s_wh_end_wait2,
    s_wh_end_wait3,
    s_wh_end_wait4,
    -- DO WHILE START
    s_dwh_start,
    -- DO WHILE END
    s_dwh_end,
    s_dwh_end2,
    s_dwh_end3,
    s_dwh_end4,
    s_dwh_end5,
    s_dwh_end_wait,
    s_dwh_end_wait2,
    s_dwh_end_wait3,
    s_dwh_end_wait4,
    -- PRINT
    s_print,
    s_print2,
    s_print_done,
    -- LOAD
    s_load,
    s_load_done,
    -- WAIT STATE
    s_wait,
    -- NULL
    s_null
    );
    signal state      : fsm_state := s_init;
    signal next_state : fsm_state;

begin

  -- CNT
  cnt: process (CLK, RESET, cnt_inc, cnt_dec, cnt_one) is
  begin
    if (RESET = '1') then
      cnt_val <= (others => '0');
    elsif rising_edge(CLK) then
      if (cnt_inc = '1') then
        cnt_val <= cnt_val + 1;
      elsif (cnt_dec = '1') then
        cnt_val <= cnt_val - 1;
      elsif (cnt_one = '1') then
        cnt_val <= "0000000000001";
      end if;
    end if;
  end process;

  -- PC
  pc: process (CLK, RESET, pc_inc, pc_dec) is
  begin
    if (RESET = '1') then
      pc_val <= (others => '0');
    elsif rising_edge(CLK) then
      if (pc_inc = '1') then
        pc_val <= pc_val + 1;
      elsif (pc_dec = '1') then
        pc_val <= pc_val - 1;
        end if;
    end if;
  end process;

-- PTR
ptr: process (CLK, RESET, ptr_inc, ptr_dec) is
  begin
    if (RESET = '1') then
      ptr_val <= (others => '0');
    elsif rising_edge(CLK) then
      if (ptr_inc = '1') then
        ptr_val <= ptr_val + 1;
      elsif (ptr_dec = '1') then
        ptr_val <= ptr_val - 1;
        end if;
    end if;
  end process;

-- MUX1
  mux1: process (CLK, RESET, mux1_select) is
  begin
    if (RESET = '1') then
      mux1_out <= (others => '0');
    elsif rising_edge(CLK) then
      case mux1_select is
        when '1' =>
          mux1_out <= '1' & ptr_val;
        when '0' =>
          mux1_out <= '0' & pc_val;
        when others =>
          mux1_out <= (others => '0');
        end case;
    end if;
  end process;
  DATA_ADDR <= mux1_out;

-- ALTERNATIVA MUX1

--DATA_ADDR <= '1' & ptr_val when (mux1_select = '1') else
--             '0' & pc_val when (mux1_select = '0') else
--             (others => '0');

-- MUX2
mux2: process (CLK, RESET, mux2_select) is
  begin
    if (RESET = '1') then
      mux2_out <= (others => '0');
    elsif rising_edge(CLK) then
      case mux2_select is
        when "00" =>
          mux2_out <= IN_DATA;
        when "01" =>
          mux2_out <= DATA_RDATA + 1;
        when "10" =>
          mux2_out <= DATA_RDATA - 1;
        when others =>
          mux2_out <= (others => '0');
        end case;
    end if;
  end process;
  DATA_WDATA <= mux2_out;

  -- FSM
  fsm_state_process : process (CLK, RESET, EN) is
    begin
      if (RESET = '1') then
        state <= s_init;
      elsif rising_edge(CLK) then
        if (EN = '1') then
          state <= next_state;
        end if;
      end if;
    end process;

  fsm_next_state_process : process (state, IN_VLD, OUT_BUSY, DATA_RDATA, EN) is
    begin
      cnt_inc <= '0';
      cnt_dec <= '0';
      cnt_one <= '0';

      pc_inc <= '0';
      pc_dec <= '0';

      ptr_inc <= '0';
      ptr_dec <= '0';

      mux1_select <= '0';
      mux2_select <= "11"; -- 00
      
      OUT_WE    <= '0';
      IN_REQ    <= '0';
      DATA_RDWR <= '0';
      DATA_EN   <= '0';

      case state is
        when s_init =>
          next_state <= s_fetch;
        when s_fetch =>
          DATA_EN <= '1';
          next_state <= s_decode;
        when s_decode =>
            case DATA_RDATA is
              when X"3E" =>
                next_state <= s_ptr_inc;
              when X"3C" =>
                next_state <= s_ptr_dec;
              when X"2B" =>
                next_state <= s_val_inc;
                mux1_select <= '1';
              when X"2D" =>
                mux1_select <= '1';
                next_state <= s_val_dec;
              when X"5B" =>
                next_state <= s_wh_start;
              when X"5D" =>
                next_state <= s_wh_end;
              when X"28" =>
                next_state <= s_dwh_start;
              when X"29" =>
                next_state <= s_dwh_end;
              when X"2E" =>
                mux1_select <= '1';
                next_state <= s_print;
              when X"2C" =>
                next_state <= s_load;
              when X"00" =>
                next_state <= s_null;
              when others =>
                pc_inc <= '1';
                next_state <= s_wait;
            end case;
        -- >
        when s_ptr_inc =>
          pc_inc <= '1';
          ptr_inc <= '1';
          next_state <= s_wait;
        -- <
        when s_ptr_dec =>
          pc_inc <= '1';
          ptr_dec <= '1';
          next_state <= s_wait;
        -- +
        when s_val_inc =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_val_load_inc;
        -- +
        when s_val_load_inc =>
          mux1_select <= '1';
          mux2_select <= "01";
          next_state <= s_val_end_inc;
        -- +
        when s_val_end_inc =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '1';
          pc_inc <= '1';
          next_state <= s_wait;

        -- -
        when s_val_dec =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_val_load_dec;
        -- -
        when s_val_load_dec =>
          mux1_select <= '1';
          mux2_select <= "10";
          next_state <= s_val_end_dec;
        -- -
        when s_val_end_dec =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '1';
          pc_inc <= '1';
          next_state <= s_wait;

        -- .
        when s_print =>
          if (OUT_BUSY = '1') then
            next_state <= s_print;
          else
            mux1_select <= '1';
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            next_state <= s_print2;
          end if;

        when s_print2 =>
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_print_done;

        -- .
        when s_print_done =>
          mux1_select <= '1';
          OUT_DATA <= DATA_RDATA;
          OUT_WE <= '1';
          pc_inc <= '1';
          next_state <= s_wait;
        -- ,
        when s_load =>
          IN_REQ <= '1';
          if (IN_VLD /= '1') then
            next_state <= s_load;
          else
            mux1_select <= '1';
            mux2_select <= "00"; --
            next_state <= s_load_done;
          end if;
        -- ,
        when s_load_done =>
          mux1_select <= '1';
          mux2_select <= "00";
          DATA_EN <= '1';
          DATA_RDWR <= '1';
          pc_inc <= '1';
          next_state <= s_wait;

        -- [
        when s_wh_start => 
          pc_inc <= '1';  -- PC = PC + 1
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_wh_start_wait3;

        when s_wh_start_wait3 =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_wh_start_wait4;

        when s_wh_start_wait4 =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_wh_start2;  

        when s_wh_start2 =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          if (DATA_RDATA = "00000000") then -- if (mem[ptr] == 0)
            cnt_one <= '1';                 -- CNT = 1
            DATA_EN <= '1';
            next_state <= s_wh_start3;
          else
            next_state <= s_wait;
          end if;

        when s_wh_start3 =>
          if (cnt_val = "0000000000000") then 
            next_state <= s_wait;
          else
            mux1_select <= '0';    -- while (CNT != 0)
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            next_state <= s_wh_start_wait;
          end if;

        when s_wh_start_wait =>
          mux1_select <= '0';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_wh_start_wait2;
        
        when s_wh_start_wait2 =>
          mux1_select <= '0';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_wh_start4;

        when s_wh_start4 =>
          mux1_select <= '0';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          if (DATA_RDATA = X"5B") then    -- if (mem[pc] == '[')
            cnt_inc <= '1';               -- CNT = CNT + 1
          elsif (DATA_RDATA = X"5D") then -- elsif (mem[pc] == ']')
            cnt_dec <= '1';               -- CNT = CNT - 1
          end if;

          pc_inc <= '1';                  -- PC = PC + 1
          next_state <= s_wh_start3;

        -- ]
        when s_wh_end =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_wh_end_wait3;

        when s_wh_end_wait3 =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_wh_end_wait4;

        when s_wh_end_wait4 =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_wh_end2;    
            
        when s_wh_end2 =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          if (DATA_RDATA = "00000000") then -- if (mem[ptr] == 0)
            pc_inc <= '1';                  -- PC = PC + 1
            next_state <= s_wait;
          else                              -- else
            cnt_one <= '1'; -- CNT = 1
            pc_dec <= '1';  -- PC = PC - 1
            next_state <= s_wh_end3;
          end if;

        when s_wh_end3 =>
          if (cnt_val = "0000000000000") then 
            next_state <= s_wait;
          else
            mux1_select <= '0';    -- while (CNT != 0)
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            next_state <= s_wh_end_wait;
          end if;

        when s_wh_end_wait =>
          mux1_select <= '0';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_wh_end_wait2;
        
        when s_wh_end_wait2 =>
          mux1_select <= '0';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_wh_end4;

        when s_wh_end4 =>
          mux1_select <= '0';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          if (DATA_RDATA = X"5D") then    -- if (mem[pc] == ']')
            cnt_inc <= '1';               -- CNT = CNT + 1
          elsif (DATA_RDATA = X"5B") then -- elsif (mem[pc] == '[')
            cnt_dec <= '1';               -- CNT = CNT - 1
          elsif (DATA_RDATA = X"29") then    -- if (mem[pc] == ')')
            cnt_inc <= '1';               -- CNT = CNT + 1
          elsif (DATA_RDATA = X"28") then -- elsif (mem[pc] == '(')
            cnt_dec <= '1';               -- CNT = CNT - 1
          end if;
          next_state <= s_wh_end5;

        when s_wh_end5 =>
          if (cnt_val = "0000000000000") then
            pc_inc <= '1';
          else
            pc_dec <= '1';
          end if;
          next_state <= s_wh_end3;
        
        -- (
        when s_dwh_start =>
          pc_inc <= '1';
          next_state <= s_wait;

        -- )
        when s_dwh_end =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_dwh_end_wait3;

        when s_dwh_end_wait3 =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_dwh_end_wait4;

        when s_dwh_end_wait4 =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_dwh_end2;    
            
        when s_dwh_end2 =>
          mux1_select <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          if (DATA_RDATA = "00000000") then -- if (mem[ptr] == 0)
            pc_inc <= '1';                  -- PC = PC + 1
            next_state <= s_wait;
          else                              -- else
            cnt_one <= '1'; -- CNT = 1
            pc_dec <= '1';  -- PC = PC - 1
            next_state <= s_dwh_end3;
          end if;

        when s_dwh_end3 =>
          if (cnt_val = "0000000000000") then 
            next_state <= s_wait;
          else
            mux1_select <= '0';    -- while (CNT != 0)
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            next_state <= s_dwh_end_wait;
          end if;

        when s_dwh_end_wait =>
          mux1_select <= '0';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_dwh_end_wait2;
        
        when s_dwh_end_wait2 =>
          mux1_select <= '0';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          next_state <= s_dwh_end4;

        when s_dwh_end4 =>
          mux1_select <= '0';
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          if (DATA_RDATA = X"29") then    -- if (mem[pc] == ')')
            cnt_inc <= '1';               -- CNT = CNT + 1
          elsif (DATA_RDATA = X"28") then -- elsif (mem[pc] == '(')
            cnt_dec <= '1';               -- CNT = CNT - 1
          elsif (DATA_RDATA = X"5D") then    -- if (mem[pc] == ']')
            cnt_inc <= '1';               -- CNT = CNT + 1
          elsif (DATA_RDATA = X"5B") then -- elsif (mem[pc] == '[')
            cnt_dec <= '1';               -- CNT = CNT - 1
          end if;
          next_state <= s_dwh_end5;

        when s_dwh_end5 =>
          if (cnt_val = "0000000000000") then
            pc_inc <= '1';
          else
            pc_dec <= '1';
          end if;
          next_state <= s_dwh_end3;

        -- WAIT
        when s_wait =>
          -- mux1_select <= '0';
          next_state <= s_fetch;

          -- null
        when s_null =>
          next_state <= s_null;

      end case;
    end process;

end behavioral;

