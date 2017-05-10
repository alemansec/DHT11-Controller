library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity datapath is
  generic(with_prescaler : boolean := false);
  port(
       data_in          :           in std_ulogic;
       SW0		: 	    in    std_ulogic;
       SW1		: 	    in    std_ulogic;
       SW2		: 	    in    std_ulogic;
       SW3		: 	    in    std_ulogic;
       rst		:	    in    std_ulogic;
       master_clk	:	    in    std_ulogic;
       en               :           in    std_ulogic;
       init_enable      :           in    std_ulogic;    --when enabled final count is set to the value present on init_counter
       BTN		:	    in    std_ulogic;
       shift_enable     :           in    std_ulogic;
       busy_bit         :           in    std_ulogic;
       protocol_error   :           in    std_ulogic;
       init_counter     :           in    integer;
       data             :           in    std_ulogic;
       final_cnt	:           out   std_ulogic;
       final_count	:           out   std_ulogic;
       pulse		:           out   std_ulogic;
       fall_edge	:           out   std_ulogic;
       LEDs             :           out   std_ulogic_vector(3 DOWNTO 0)
  );
end entity datapath;


architecture beh of datapath is
  signal sipo_out_mux_in	:  std_ulogic_vector(31 DOWNTO 0);
  signal checksum		:  std_ulogic_vector(7 DOWNTO 0);
  signal nib_sel_to_A		:  std_ulogic_vector(3 DOWNTO 0);
  signal checksum_ver_to_B      :  std_ulogic_vector(3 DOWNTO 0);
  signal Q			:  std_ulogic_vector(39 DOWNTO 0);
  signal cnt                    :  integer range 0 to 40;
  signal clk      		:  std_ulogic;
  signal prescaler_clk   	:  std_ulogic;
  signal count                  :  integer;
  signal threshold              :  integer;
  signal dp			: std_ulogic_vector(2 downto 0);

begin

  --data    <= '0' when data_drv = '1' else 'H';
  --data_in <= data;

  SIPO: process(master_clk)
  variable Q_var:  std_ulogic_vector(39 DOWNTO 0);
  begin
    if(master_clk'event and master_clk = '1') then
      final_count <= '0';
      if rst = '1' then
      	Q <= (others=>'0');
      	sipo_out_mux_in <= (others=>'0');
      	checksum <= (others=>'0');
      	cnt <= 0;
      elsif(shift_enable='1') then
        if cnt < 39 then
          -- Left shift
          Q <= Q(38 downto 0) & data;
          cnt <= cnt + 1;
        else
          final_count <= '1';
          cnt <= 0;
          Q_var := Q(38 downto 0) & data;
          sipo_out_mux_in <= Q_var(39 DOWNTO 8);
          checksum <= Q_var(7 DOWNTO 0);
         end if;
       end if;
    end if;
  end process SIPO;

  MUXes: process(sipo_out_mux_in, SW0, SW1, SW2)
  begin
    nib_sel_to_A <= sipo_out_mux_in(3 DOWNTO 0) when SW0='0' and SW1='0' and SW2='0' else
      sipo_out_mux_in(7 DOWNTO 4) when SW0='0' and SW1='0' and SW2='1' else
      sipo_out_mux_in(11 DOWNTO 8) when SW0='0' and SW1='1' and SW2='0' else
      sipo_out_mux_in(15 DOWNTO 12) when SW0='0' and SW1='1' and SW2='1' else
      sipo_out_mux_in(19 DOWNTO 16) when SW0='1' and SW1='0' and SW2='0' else
      sipo_out_mux_in(23 DOWNTO 20) when SW0='1' and SW1='0' and SW2='1' else
      sipo_out_mux_in(27 DOWNTO 24) when SW0='1' and SW1='1' and SW2='0' else
      sipo_out_mux_in(31 DOWNTO 28) when SW0='1' and SW1='1' and SW2='1';
  end process MUXes;

  Checksum_controller: process(checksum, sipo_out_mux_in)
  variable sum: std_ulogic_vector(7 DOWNTO 0);
  begin
    sum:= sipo_out_mux_in(31 DOWNTO 24) + sipo_out_mux_in(23 DOWNTO 16) + sipo_out_mux_in(15 DOWNTO 8) + sipo_out_mux_in(7 DOWNTO 0);
    if sum = checksum then
      checksum_ver_to_B(0) <= '0';
    else
      checksum_ver_to_B(0) <= '1';
    end if;
  end process Checksum_controller;

  checksum_ver_to_B(1) <= busy_bit;
  checksum_ver_to_B(2) <= SW0;
  checksum_ver_to_B(3) <= protocol_error;

  MUX: process(nib_sel_to_A, checksum_ver_to_B, SW3)
  begin
    LEDs <= nib_sel_to_A when (SW3 = '1') else checksum_ver_to_B;
  end process MUX;

  PRESCALER: entity work.prescaler(arc)
    generic map(
      max => 0
    )
    port map(
      clk     => master_clk,
      sreset  => rst,
      fc      => prescaler_clk
    );

  process(prescaler_clk, master_clk)
  begin
    if with_prescaler then
      clk <= prescaler_clk;
    else
      clk <= master_clk;
    end if;
  end process;

  COUNTER: process(clk)
  begin
    if(clk'event and clk='1') then
        final_cnt <= '0';
        if(rst='0') then
            count <= 0;
        elsif(init_enable = '1') then
            threshold <= init_counter;
            count <= 0; --To be decided if reset or not
        elsif(en = '1') then
            if(count = threshold - 1) then
                final_cnt <= '1';
                count <= 0;
            else
                count <= count + 1;
            end if;
        end if;
    end if;
  end process COUNTER;

  Debouncer: entity work.debouncer(rtl)
    generic map(
      n0 => 50000, -- sampling counter wrapping value
      n1 => 10     -- debouncing counter maximum value
    )
    port map(
      clk     => clk,
      srstn   => rst,
      d       => BTN,
      q       => open,
      r       => open,
      f       => fall_edge,
      a       => open
    );

  PULSE_GEN: process(clk)
  begin
    if(clk' event and clk='1') then
      dp <= data_in & dp(2 downto 1);
    end if;
  end process;
  pulse <= dp(1) xor dp(0);

end architecture beh;
