<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE eagle SYSTEM "eagle.dtd">
<eagle version="9.6.2">
<drawing>
<settings><setting alwaysvectorfont="no"/><setting verticaltext="up"/></settings>
<grid distance="0.1" unitdist="inch" unit="inch" style="lines" multiple="1" display="no" altdistance="0.01" altunitdist="inch" altunit="inch"/>
<layers>
<layer number="1" name="Top" color="4" fill="1" visible="yes" active="yes"/>
<layer number="2" name="Route2" color="1" fill="1" visible="yes" active="yes"/>
<layer number="3" name="Route3" color="4" fill="1" visible="yes" active="yes"/>
<layer number="4" name="Route4" color="1" fill="1" visible="yes" active="yes"/>
<layer number="5" name="Route5" color="4" fill="1" visible="yes" active="yes"/>
<layer number="6" name="Route6" color="1" fill="1" visible="yes" active="yes"/>
<layer number="7" name="Route7" color="4" fill="1" visible="yes" active="yes"/>
<layer number="8" name="Route8" color="1" fill="1" visible="yes" active="yes"/>
<layer number="9" name="Route9" color="4" fill="1" visible="yes" active="yes"/>
<layer number="10" name="Route10" color="1" fill="1" visible="yes" active="yes"/>
<layer number="11" name="Route11" color="4" fill="1" visible="yes" active="yes"/>
<layer number="12" name="Route12" color="1" fill="1" visible="yes" active="yes"/>
<layer number="13" name="Route13" color="4" fill="1" visible="yes" active="yes"/>
<layer number="14" name="Route14" color="1" fill="1" visible="yes" active="yes"/>
<layer number="15" name="Route15" color="4" fill="1" visible="yes" active="yes"/>
<layer number="16" name="Bottom" color="1" fill="1" visible="yes" active="yes"/>
<layer number="17" name="Pads" color="2" fill="1" visible="yes" active="yes"/>
<layer number="18" name="Vias" color="2" fill="1" visible="yes" active="yes"/>
<layer number="19" name="Unrouted" color="6" fill="1" visible="yes" active="yes"/>
<layer number="20" name="Dimension" color="24" fill="1" visible="yes" active="yes"/>
<layer number="21" name="tPlace" color="7" fill="1" visible="yes" active="yes"/>
<layer number="22" name="bPlace" color="7" fill="1" visible="yes" active="yes"/>
<layer number="23" name="tOrigins" color="15" fill="1" visible="yes" active="yes"/>
<layer number="24" name="bOrigins" color="15" fill="1" visible="yes" active="yes"/>
<layer number="25" name="tNames" color="7" fill="1" visible="yes" active="yes"/>
<layer number="26" name="bNames" color="7" fill="1" visible="yes" active="yes"/>
<layer number="27" name="tValues" color="7" fill="1" visible="yes" active="yes"/>
<layer number="28" name="bValues" color="7" fill="1" visible="yes" active="yes"/>
<layer number="29" name="tStop" color="7" fill="3" visible="yes" active="yes"/>
<layer number="30" name="bStop" color="7" fill="6" visible="yes" active="yes"/>
<layer number="31" name="tCream" color="7" fill="4" visible="yes" active="yes"/>
<layer number="32" name="bCream" color="7" fill="5" visible="yes" active="yes"/>
<layer number="33" name="tFinish" color="6" fill="3" visible="yes" active="yes"/>
<layer number="34" name="bFinish" color="6" fill="6" visible="yes" active="yes"/>
<layer number="35" name="tGlue" color="7" fill="4" visible="yes" active="yes"/>
<layer number="36" name="bGlue" color="7" fill="5" visible="yes" active="yes"/>
<layer number="37" name="tTest" color="7" fill="1" visible="yes" active="yes"/>
<layer number="38" name="bTest" color="7" fill="1" visible="yes" active="yes"/>
<layer number="39" name="tKeepout" color="4" fill="11" visible="yes" active="yes"/>
<layer number="40" name="bKeepout" color="1" fill="11" visible="yes" active="yes"/>
<layer number="41" name="tRestrict" color="4" fill="10" visible="yes" active="yes"/>
<layer number="42" name="bRestrict" color="1" fill="10" visible="yes" active="yes"/>
<layer number="43" name="vRestrict" color="2" fill="10" visible="yes" active="yes"/>
<layer number="44" name="Drills" color="7" fill="1" visible="yes" active="yes"/>
<layer number="45" name="Holes" color="7" fill="1" visible="yes" active="yes"/>
<layer number="46" name="Milling" color="3" fill="1" visible="yes" active="yes"/>
<layer number="47" name="Measures" color="7" fill="1" visible="yes" active="yes"/>
<layer number="48" name="Document" color="7" fill="1" visible="yes" active="yes"/>
<layer number="49" name="Reference" color="7" fill="1" visible="yes" active="yes"/>
<layer number="51" name="tDocu" color="7" fill="1" visible="yes" active="yes"/>
<layer number="52" name="bDocu" color="7" fill="1" visible="yes" active="yes"/>
<layer number="88" name="SimResults" color="9" fill="1" visible="yes" active="yes"/>
<layer number="89" name="SimProbes" color="9" fill="1" visible="yes" active="yes"/>
<layer number="90" name="Modules" color="5" fill="1" visible="yes" active="yes"/>
<layer number="91" name="Nets" color="2" fill="1" visible="yes" active="yes"/>
<layer number="92" name="Busses" color="1" fill="1" visible="yes" active="yes"/>
<layer number="93" name="Pins" color="2" fill="1" visible="yes" active="yes"/>
<layer number="94" name="Symbols" color="4" fill="1" visible="yes" active="yes"/>
<layer number="95" name="Names" color="7" fill="1" visible="yes" active="yes"/>
<layer number="96" name="Values" color="7" fill="1" visible="yes" active="yes"/>
<layer number="97" name="Info" color="7" fill="1" visible="yes" active="yes"/>
<layer number="98" name="Guide" color="6" fill="1" visible="yes" active="yes"/>
</layers>
<schematic xreflabel="%F%N/%S.%C%R" xrefpart="/%S.%C%R">
<libraries><library name="p8x">
<packages>
<package name="C_DISC">
<pad name="1" x="0.00" y="0.00" drill="0.9" diameter="1.8"/>
<pad name="2" x="0.00" y="-5.08" drill="0.9" diameter="1.8"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="DIN96">
<pad name="A1" x="5.08" y="-0.00" drill="1.0" diameter="1.7"/>
<pad name="A2" x="5.08" y="-2.54" drill="1.0" diameter="1.7"/>
<pad name="A3" x="5.08" y="-5.08" drill="1.0" diameter="1.7"/>
<pad name="A4" x="5.08" y="-7.62" drill="1.0" diameter="1.7"/>
<pad name="A5" x="5.08" y="-10.16" drill="1.0" diameter="1.7"/>
<pad name="A6" x="5.08" y="-12.70" drill="1.0" diameter="1.7"/>
<pad name="A7" x="5.08" y="-15.24" drill="1.0" diameter="1.7"/>
<pad name="A8" x="5.08" y="-17.78" drill="1.0" diameter="1.7"/>
<pad name="A9" x="5.08" y="-20.32" drill="1.0" diameter="1.7"/>
<pad name="A10" x="5.08" y="-22.86" drill="1.0" diameter="1.7"/>
<pad name="A11" x="5.08" y="-25.40" drill="1.0" diameter="1.7"/>
<pad name="A12" x="5.08" y="-27.94" drill="1.0" diameter="1.7"/>
<pad name="A13" x="5.08" y="-30.48" drill="1.0" diameter="1.7"/>
<pad name="A14" x="5.08" y="-33.02" drill="1.0" diameter="1.7"/>
<pad name="A15" x="5.08" y="-35.56" drill="1.0" diameter="1.7"/>
<pad name="A16" x="5.08" y="-38.10" drill="1.0" diameter="1.7"/>
<pad name="A17" x="5.08" y="-40.64" drill="1.0" diameter="1.7"/>
<pad name="A18" x="5.08" y="-43.18" drill="1.0" diameter="1.7"/>
<pad name="A19" x="5.08" y="-45.72" drill="1.0" diameter="1.7"/>
<pad name="A20" x="5.08" y="-48.26" drill="1.0" diameter="1.7"/>
<pad name="A21" x="5.08" y="-50.80" drill="1.0" diameter="1.7"/>
<pad name="A22" x="5.08" y="-53.34" drill="1.0" diameter="1.7"/>
<pad name="A23" x="5.08" y="-55.88" drill="1.0" diameter="1.7"/>
<pad name="A24" x="5.08" y="-58.42" drill="1.0" diameter="1.7"/>
<pad name="A25" x="5.08" y="-60.96" drill="1.0" diameter="1.7"/>
<pad name="A26" x="5.08" y="-63.50" drill="1.0" diameter="1.7"/>
<pad name="A27" x="5.08" y="-66.04" drill="1.0" diameter="1.7"/>
<pad name="A28" x="5.08" y="-68.58" drill="1.0" diameter="1.7"/>
<pad name="A29" x="5.08" y="-71.12" drill="1.0" diameter="1.7"/>
<pad name="A30" x="5.08" y="-73.66" drill="1.0" diameter="1.7"/>
<pad name="A31" x="5.08" y="-76.20" drill="1.0" diameter="1.7"/>
<pad name="A32" x="5.08" y="-78.74" drill="1.0" diameter="1.7"/>
<pad name="B1" x="2.54" y="-0.00" drill="1.0" diameter="1.7"/>
<pad name="B2" x="2.54" y="-2.54" drill="1.0" diameter="1.7"/>
<pad name="B3" x="2.54" y="-5.08" drill="1.0" diameter="1.7"/>
<pad name="B4" x="2.54" y="-7.62" drill="1.0" diameter="1.7"/>
<pad name="B5" x="2.54" y="-10.16" drill="1.0" diameter="1.7"/>
<pad name="B6" x="2.54" y="-12.70" drill="1.0" diameter="1.7"/>
<pad name="B7" x="2.54" y="-15.24" drill="1.0" diameter="1.7"/>
<pad name="B8" x="2.54" y="-17.78" drill="1.0" diameter="1.7"/>
<pad name="B9" x="2.54" y="-20.32" drill="1.0" diameter="1.7"/>
<pad name="B10" x="2.54" y="-22.86" drill="1.0" diameter="1.7"/>
<pad name="B11" x="2.54" y="-25.40" drill="1.0" diameter="1.7"/>
<pad name="B12" x="2.54" y="-27.94" drill="1.0" diameter="1.7"/>
<pad name="B13" x="2.54" y="-30.48" drill="1.0" diameter="1.7"/>
<pad name="B14" x="2.54" y="-33.02" drill="1.0" diameter="1.7"/>
<pad name="B15" x="2.54" y="-35.56" drill="1.0" diameter="1.7"/>
<pad name="B16" x="2.54" y="-38.10" drill="1.0" diameter="1.7"/>
<pad name="B17" x="2.54" y="-40.64" drill="1.0" diameter="1.7"/>
<pad name="B18" x="2.54" y="-43.18" drill="1.0" diameter="1.7"/>
<pad name="B19" x="2.54" y="-45.72" drill="1.0" diameter="1.7"/>
<pad name="B20" x="2.54" y="-48.26" drill="1.0" diameter="1.7"/>
<pad name="B21" x="2.54" y="-50.80" drill="1.0" diameter="1.7"/>
<pad name="B22" x="2.54" y="-53.34" drill="1.0" diameter="1.7"/>
<pad name="B23" x="2.54" y="-55.88" drill="1.0" diameter="1.7"/>
<pad name="B24" x="2.54" y="-58.42" drill="1.0" diameter="1.7"/>
<pad name="B25" x="2.54" y="-60.96" drill="1.0" diameter="1.7"/>
<pad name="B26" x="2.54" y="-63.50" drill="1.0" diameter="1.7"/>
<pad name="B27" x="2.54" y="-66.04" drill="1.0" diameter="1.7"/>
<pad name="B28" x="2.54" y="-68.58" drill="1.0" diameter="1.7"/>
<pad name="B29" x="2.54" y="-71.12" drill="1.0" diameter="1.7"/>
<pad name="B30" x="2.54" y="-73.66" drill="1.0" diameter="1.7"/>
<pad name="B31" x="2.54" y="-76.20" drill="1.0" diameter="1.7"/>
<pad name="B32" x="2.54" y="-78.74" drill="1.0" diameter="1.7"/>
<pad name="C1" x="0.00" y="-0.00" drill="1.0" diameter="1.7"/>
<pad name="C2" x="0.00" y="-2.54" drill="1.0" diameter="1.7"/>
<pad name="C3" x="0.00" y="-5.08" drill="1.0" diameter="1.7"/>
<pad name="C4" x="0.00" y="-7.62" drill="1.0" diameter="1.7"/>
<pad name="C5" x="0.00" y="-10.16" drill="1.0" diameter="1.7"/>
<pad name="C6" x="0.00" y="-12.70" drill="1.0" diameter="1.7"/>
<pad name="C7" x="0.00" y="-15.24" drill="1.0" diameter="1.7"/>
<pad name="C8" x="0.00" y="-17.78" drill="1.0" diameter="1.7"/>
<pad name="C9" x="0.00" y="-20.32" drill="1.0" diameter="1.7"/>
<pad name="C10" x="0.00" y="-22.86" drill="1.0" diameter="1.7"/>
<pad name="C11" x="0.00" y="-25.40" drill="1.0" diameter="1.7"/>
<pad name="C12" x="0.00" y="-27.94" drill="1.0" diameter="1.7"/>
<pad name="C13" x="0.00" y="-30.48" drill="1.0" diameter="1.7"/>
<pad name="C14" x="0.00" y="-33.02" drill="1.0" diameter="1.7"/>
<pad name="C15" x="0.00" y="-35.56" drill="1.0" diameter="1.7"/>
<pad name="C16" x="0.00" y="-38.10" drill="1.0" diameter="1.7"/>
<pad name="C17" x="0.00" y="-40.64" drill="1.0" diameter="1.7"/>
<pad name="C18" x="0.00" y="-43.18" drill="1.0" diameter="1.7"/>
<pad name="C19" x="0.00" y="-45.72" drill="1.0" diameter="1.7"/>
<pad name="C20" x="0.00" y="-48.26" drill="1.0" diameter="1.7"/>
<pad name="C21" x="0.00" y="-50.80" drill="1.0" diameter="1.7"/>
<pad name="C22" x="0.00" y="-53.34" drill="1.0" diameter="1.7"/>
<pad name="C23" x="0.00" y="-55.88" drill="1.0" diameter="1.7"/>
<pad name="C24" x="0.00" y="-58.42" drill="1.0" diameter="1.7"/>
<pad name="C25" x="0.00" y="-60.96" drill="1.0" diameter="1.7"/>
<pad name="C26" x="0.00" y="-63.50" drill="1.0" diameter="1.7"/>
<pad name="C27" x="0.00" y="-66.04" drill="1.0" diameter="1.7"/>
<pad name="C28" x="0.00" y="-68.58" drill="1.0" diameter="1.7"/>
<pad name="C29" x="0.00" y="-71.12" drill="1.0" diameter="1.7"/>
<pad name="C30" x="0.00" y="-73.66" drill="1.0" diameter="1.7"/>
<pad name="C31" x="0.00" y="-76.20" drill="1.0" diameter="1.7"/>
<pad name="C32" x="0.00" y="-78.74" drill="1.0" diameter="1.7"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="DIP14">
<pad name="1" x="0.00" y="-0.00" drill="0.8128" diameter="1.6"/>
<pad name="2" x="0.00" y="-2.54" drill="0.8128" diameter="1.6"/>
<pad name="3" x="0.00" y="-5.08" drill="0.8128" diameter="1.6"/>
<pad name="4" x="0.00" y="-7.62" drill="0.8128" diameter="1.6"/>
<pad name="5" x="0.00" y="-10.16" drill="0.8128" diameter="1.6"/>
<pad name="6" x="0.00" y="-12.70" drill="0.8128" diameter="1.6"/>
<pad name="7" x="0.00" y="-15.24" drill="0.8128" diameter="1.6"/>
<pad name="8" x="7.62" y="-15.24" drill="0.8128" diameter="1.6"/>
<pad name="9" x="7.62" y="-12.70" drill="0.8128" diameter="1.6"/>
<pad name="10" x="7.62" y="-10.16" drill="0.8128" diameter="1.6"/>
<pad name="11" x="7.62" y="-7.62" drill="0.8128" diameter="1.6"/>
<pad name="12" x="7.62" y="-5.08" drill="0.8128" diameter="1.6"/>
<pad name="13" x="7.62" y="-2.54" drill="0.8128" diameter="1.6"/>
<pad name="14" x="7.62" y="-0.00" drill="0.8128" diameter="1.6"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="DIP16">
<pad name="1" x="0.00" y="-0.00" drill="0.8128" diameter="1.6"/>
<pad name="2" x="0.00" y="-2.54" drill="0.8128" diameter="1.6"/>
<pad name="3" x="0.00" y="-5.08" drill="0.8128" diameter="1.6"/>
<pad name="4" x="0.00" y="-7.62" drill="0.8128" diameter="1.6"/>
<pad name="5" x="0.00" y="-10.16" drill="0.8128" diameter="1.6"/>
<pad name="6" x="0.00" y="-12.70" drill="0.8128" diameter="1.6"/>
<pad name="7" x="0.00" y="-15.24" drill="0.8128" diameter="1.6"/>
<pad name="8" x="0.00" y="-17.78" drill="0.8128" diameter="1.6"/>
<pad name="9" x="7.62" y="-17.78" drill="0.8128" diameter="1.6"/>
<pad name="10" x="7.62" y="-15.24" drill="0.8128" diameter="1.6"/>
<pad name="11" x="7.62" y="-12.70" drill="0.8128" diameter="1.6"/>
<pad name="12" x="7.62" y="-10.16" drill="0.8128" diameter="1.6"/>
<pad name="13" x="7.62" y="-7.62" drill="0.8128" diameter="1.6"/>
<pad name="14" x="7.62" y="-5.08" drill="0.8128" diameter="1.6"/>
<pad name="15" x="7.62" y="-2.54" drill="0.8128" diameter="1.6"/>
<pad name="16" x="7.62" y="-0.00" drill="0.8128" diameter="1.6"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="DIP20">
<pad name="1" x="0.00" y="-0.00" drill="0.8128" diameter="1.6"/>
<pad name="2" x="0.00" y="-2.54" drill="0.8128" diameter="1.6"/>
<pad name="3" x="0.00" y="-5.08" drill="0.8128" diameter="1.6"/>
<pad name="4" x="0.00" y="-7.62" drill="0.8128" diameter="1.6"/>
<pad name="5" x="0.00" y="-10.16" drill="0.8128" diameter="1.6"/>
<pad name="6" x="0.00" y="-12.70" drill="0.8128" diameter="1.6"/>
<pad name="7" x="0.00" y="-15.24" drill="0.8128" diameter="1.6"/>
<pad name="8" x="0.00" y="-17.78" drill="0.8128" diameter="1.6"/>
<pad name="9" x="0.00" y="-20.32" drill="0.8128" diameter="1.6"/>
<pad name="10" x="0.00" y="-22.86" drill="0.8128" diameter="1.6"/>
<pad name="11" x="7.62" y="-22.86" drill="0.8128" diameter="1.6"/>
<pad name="12" x="7.62" y="-20.32" drill="0.8128" diameter="1.6"/>
<pad name="13" x="7.62" y="-17.78" drill="0.8128" diameter="1.6"/>
<pad name="14" x="7.62" y="-15.24" drill="0.8128" diameter="1.6"/>
<pad name="15" x="7.62" y="-12.70" drill="0.8128" diameter="1.6"/>
<pad name="16" x="7.62" y="-10.16" drill="0.8128" diameter="1.6"/>
<pad name="17" x="7.62" y="-7.62" drill="0.8128" diameter="1.6"/>
<pad name="18" x="7.62" y="-5.08" drill="0.8128" diameter="1.6"/>
<pad name="19" x="7.62" y="-2.54" drill="0.8128" diameter="1.6"/>
<pad name="20" x="7.62" y="-0.00" drill="0.8128" diameter="1.6"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="DIP28W">
<pad name="1" x="0.00" y="-0.00" drill="0.8128" diameter="1.6"/>
<pad name="2" x="0.00" y="-2.54" drill="0.8128" diameter="1.6"/>
<pad name="3" x="0.00" y="-5.08" drill="0.8128" diameter="1.6"/>
<pad name="4" x="0.00" y="-7.62" drill="0.8128" diameter="1.6"/>
<pad name="5" x="0.00" y="-10.16" drill="0.8128" diameter="1.6"/>
<pad name="6" x="0.00" y="-12.70" drill="0.8128" diameter="1.6"/>
<pad name="7" x="0.00" y="-15.24" drill="0.8128" diameter="1.6"/>
<pad name="8" x="0.00" y="-17.78" drill="0.8128" diameter="1.6"/>
<pad name="9" x="0.00" y="-20.32" drill="0.8128" diameter="1.6"/>
<pad name="10" x="0.00" y="-22.86" drill="0.8128" diameter="1.6"/>
<pad name="11" x="0.00" y="-25.40" drill="0.8128" diameter="1.6"/>
<pad name="12" x="0.00" y="-27.94" drill="0.8128" diameter="1.6"/>
<pad name="13" x="0.00" y="-30.48" drill="0.8128" diameter="1.6"/>
<pad name="14" x="0.00" y="-33.02" drill="0.8128" diameter="1.6"/>
<pad name="15" x="15.24" y="-33.02" drill="0.8128" diameter="1.6"/>
<pad name="16" x="15.24" y="-30.48" drill="0.8128" diameter="1.6"/>
<pad name="17" x="15.24" y="-27.94" drill="0.8128" diameter="1.6"/>
<pad name="18" x="15.24" y="-25.40" drill="0.8128" diameter="1.6"/>
<pad name="19" x="15.24" y="-22.86" drill="0.8128" diameter="1.6"/>
<pad name="20" x="15.24" y="-20.32" drill="0.8128" diameter="1.6"/>
<pad name="21" x="15.24" y="-17.78" drill="0.8128" diameter="1.6"/>
<pad name="22" x="15.24" y="-15.24" drill="0.8128" diameter="1.6"/>
<pad name="23" x="15.24" y="-12.70" drill="0.8128" diameter="1.6"/>
<pad name="24" x="15.24" y="-10.16" drill="0.8128" diameter="1.6"/>
<pad name="25" x="15.24" y="-7.62" drill="0.8128" diameter="1.6"/>
<pad name="26" x="15.24" y="-5.08" drill="0.8128" diameter="1.6"/>
<pad name="27" x="15.24" y="-2.54" drill="0.8128" diameter="1.6"/>
<pad name="28" x="15.24" y="-0.00" drill="0.8128" diameter="1.6"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="HDR4">
<pad name="1" x="0.00" y="-0.00" drill="0.9" diameter="1.8"/>
<pad name="2" x="0.00" y="-2.54" drill="0.9" diameter="1.8"/>
<pad name="3" x="0.00" y="-5.08" drill="0.9" diameter="1.8"/>
<pad name="4" x="0.00" y="-7.62" drill="0.9" diameter="1.8"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="LED5">
<pad name="2" x="0.00" y="0.00" drill="0.9" diameter="1.8"/>
<pad name="1" x="2.54" y="0.00" drill="0.9" diameter="1.8"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="OSC4">
<pad name="1" x="0.00" y="0.00" drill="0.8" diameter="1.6"/>
<pad name="7" x="0.00" y="-15.24" drill="0.8" diameter="1.6"/>
<pad name="8" x="7.62" y="-15.24" drill="0.8" diameter="1.6"/>
<pad name="14" x="7.62" y="0.00" drill="0.8" diameter="1.6"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="R_AXIAL">
<pad name="1" x="0.00" y="0.00" drill="0.8" diameter="1.6"/>
<pad name="2" x="10.16" y="0.00" drill="0.8" diameter="1.6"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="SW2P">
<pad name="1" x="0.00" y="0.00" drill="1.0" diameter="1.9"/>
<pad name="2" x="5.08" y="0.00" drill="1.0" diameter="1.9"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
</packages>
<symbols>
<symbol name="28C64">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-38.10" width="0.254" layer="94"/>
<wire x1="12.7" y1="-38.1" x2="-12.7" y2="-38.10" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-38.1" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-41.91" size="1.778" layer="96">&gt;VALUE</text>
<pin name="A0" x="-17.78" y="-0.00" length="middle"/>
<pin name="A1" x="-17.78" y="-2.54" length="middle"/>
<pin name="A2" x="-17.78" y="-5.08" length="middle"/>
<pin name="A3" x="-17.78" y="-7.62" length="middle"/>
<pin name="A4" x="-17.78" y="-10.16" length="middle"/>
<pin name="A5" x="-17.78" y="-12.70" length="middle"/>
<pin name="A6" x="-17.78" y="-15.24" length="middle"/>
<pin name="A7" x="-17.78" y="-17.78" length="middle"/>
<pin name="A8" x="-17.78" y="-20.32" length="middle"/>
<pin name="A9" x="-17.78" y="-22.86" length="middle"/>
<pin name="A10" x="-17.78" y="-25.40" length="middle"/>
<pin name="A11" x="-17.78" y="-27.94" length="middle"/>
<pin name="A12" x="-17.78" y="-30.48" length="middle"/>
<pin name="IO0" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="IO1" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="IO2" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="IO3" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="IO4" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="IO5" x="17.78" y="-12.70" length="middle" rot="R180"/>
<pin name="IO6" x="17.78" y="-15.24" length="middle" rot="R180"/>
<pin name="IO7" x="17.78" y="-17.78" length="middle" rot="R180"/>
<pin name="!CE" x="17.78" y="-20.32" length="middle" rot="R180"/>
<pin name="!OE" x="17.78" y="-22.86" length="middle" rot="R180"/>
<pin name="!WE" x="17.78" y="-25.40" length="middle" rot="R180"/>
<pin name="RDY" x="17.78" y="-27.94" length="middle" rot="R180"/>
<pin name="NC26" x="17.78" y="-30.48" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-33.02" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-35.56" length="middle" rot="R180"/>
</symbol>
<symbol name="74138">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-25.40" width="0.254" layer="94"/>
<wire x1="12.7" y1="-25.4" x2="-12.7" y2="-25.40" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-25.4" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-29.21" size="1.778" layer="96">&gt;VALUE</text>
<pin name="A" x="-17.78" y="-0.00" length="middle"/>
<pin name="B" x="-17.78" y="-2.54" length="middle"/>
<pin name="C" x="-17.78" y="-5.08" length="middle"/>
<pin name="G1" x="-17.78" y="-7.62" length="middle"/>
<pin name="!G2A" x="-17.78" y="-10.16" length="middle"/>
<pin name="!G2B" x="-17.78" y="-12.70" length="middle"/>
<pin name="Y0" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="Y1" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="Y2" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="Y3" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="Y4" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="Y5" x="17.78" y="-12.70" length="middle" rot="R180"/>
<pin name="Y6" x="17.78" y="-15.24" length="middle" rot="R180"/>
<pin name="Y7" x="17.78" y="-17.78" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-20.32" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-22.86" length="middle" rot="R180"/>
</symbol>
<symbol name="74151">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-30.48" width="0.254" layer="94"/>
<wire x1="12.7" y1="-30.48" x2="-12.7" y2="-30.48" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-30.48" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-34.29" size="1.778" layer="96">&gt;VALUE</text>
<pin name="A" x="-17.78" y="-0.00" length="middle"/>
<pin name="B" x="-17.78" y="-2.54" length="middle"/>
<pin name="C" x="-17.78" y="-5.08" length="middle"/>
<pin name="D0" x="-17.78" y="-7.62" length="middle"/>
<pin name="D1" x="-17.78" y="-10.16" length="middle"/>
<pin name="D2" x="-17.78" y="-12.70" length="middle"/>
<pin name="D3" x="-17.78" y="-15.24" length="middle"/>
<pin name="D4" x="-17.78" y="-17.78" length="middle"/>
<pin name="D5" x="-17.78" y="-20.32" length="middle"/>
<pin name="D6" x="-17.78" y="-22.86" length="middle"/>
<pin name="D7" x="-17.78" y="-25.40" length="middle"/>
<pin name="!G" x="-17.78" y="-27.94" length="middle"/>
<pin name="Y" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="!W" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-7.62" length="middle" rot="R180"/>
</symbol>
<symbol name="74161">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-22.86" width="0.254" layer="94"/>
<wire x1="12.7" y1="-22.86" x2="-12.7" y2="-22.86" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-22.86" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-26.67" size="1.778" layer="96">&gt;VALUE</text>
<pin name="!CLR" x="-17.78" y="-0.00" length="middle"/>
<pin name="CLK" x="-17.78" y="-2.54" length="middle"/>
<pin name="A" x="-17.78" y="-5.08" length="middle"/>
<pin name="B" x="-17.78" y="-7.62" length="middle"/>
<pin name="C" x="-17.78" y="-10.16" length="middle"/>
<pin name="D" x="-17.78" y="-12.70" length="middle"/>
<pin name="ENP" x="-17.78" y="-15.24" length="middle"/>
<pin name="!LOAD" x="-17.78" y="-17.78" length="middle"/>
<pin name="ENT" x="-17.78" y="-20.32" length="middle"/>
<pin name="QA" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="QB" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="QC" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="QD" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="RCO" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-12.70" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-15.24" length="middle" rot="R180"/>
</symbol>
<symbol name="74244">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-25.40" width="0.254" layer="94"/>
<wire x1="12.7" y1="-25.4" x2="-12.7" y2="-25.40" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-25.4" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-29.21" size="1.778" layer="96">&gt;VALUE</text>
<pin name="!G1" x="-17.78" y="-0.00" length="middle"/>
<pin name="A1" x="-17.78" y="-2.54" length="middle"/>
<pin name="A2" x="-17.78" y="-5.08" length="middle"/>
<pin name="A3" x="-17.78" y="-7.62" length="middle"/>
<pin name="A4" x="-17.78" y="-10.16" length="middle"/>
<pin name="!G2" x="-17.78" y="-12.70" length="middle"/>
<pin name="A5" x="-17.78" y="-15.24" length="middle"/>
<pin name="A6" x="-17.78" y="-17.78" length="middle"/>
<pin name="A7" x="-17.78" y="-20.32" length="middle"/>
<pin name="A8" x="-17.78" y="-22.86" length="middle"/>
<pin name="Y1" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="Y2" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="Y3" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="Y4" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="Y5" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="Y6" x="17.78" y="-12.70" length="middle" rot="R180"/>
<pin name="Y7" x="17.78" y="-15.24" length="middle" rot="R180"/>
<pin name="Y8" x="17.78" y="-17.78" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-20.32" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-22.86" length="middle" rot="R180"/>
</symbol>
<symbol name="74374">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-25.40" width="0.254" layer="94"/>
<wire x1="12.7" y1="-25.4" x2="-12.7" y2="-25.40" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-25.4" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-29.21" size="1.778" layer="96">&gt;VALUE</text>
<pin name="!OC" x="-17.78" y="-0.00" length="middle"/>
<pin name="CLK" x="-17.78" y="-2.54" length="middle"/>
<pin name="D1" x="-17.78" y="-5.08" length="middle"/>
<pin name="D2" x="-17.78" y="-7.62" length="middle"/>
<pin name="D3" x="-17.78" y="-10.16" length="middle"/>
<pin name="D4" x="-17.78" y="-12.70" length="middle"/>
<pin name="D5" x="-17.78" y="-15.24" length="middle"/>
<pin name="D6" x="-17.78" y="-17.78" length="middle"/>
<pin name="D7" x="-17.78" y="-20.32" length="middle"/>
<pin name="D8" x="-17.78" y="-22.86" length="middle"/>
<pin name="Q1" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="Q2" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="Q3" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="Q4" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="Q5" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="Q6" x="17.78" y="-12.70" length="middle" rot="R180"/>
<pin name="Q7" x="17.78" y="-15.24" length="middle" rot="R180"/>
<pin name="Q8" x="17.78" y="-17.78" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-20.32" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-22.86" length="middle" rot="R180"/>
</symbol>
<symbol name="74377V2">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-25.40" width="0.254" layer="94"/>
<wire x1="12.7" y1="-25.4" x2="-12.7" y2="-25.40" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-25.4" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-29.21" size="1.778" layer="96">&gt;VALUE</text>
<pin name="!E" x="-17.78" y="-0.00" length="middle"/>
<pin name="CLK" x="-17.78" y="-2.54" length="middle"/>
<pin name="D1" x="-17.78" y="-5.08" length="middle"/>
<pin name="D2" x="-17.78" y="-7.62" length="middle"/>
<pin name="D3" x="-17.78" y="-10.16" length="middle"/>
<pin name="D4" x="-17.78" y="-12.70" length="middle"/>
<pin name="D5" x="-17.78" y="-15.24" length="middle"/>
<pin name="D6" x="-17.78" y="-17.78" length="middle"/>
<pin name="D7" x="-17.78" y="-20.32" length="middle"/>
<pin name="D8" x="-17.78" y="-22.86" length="middle"/>
<pin name="Q1" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="Q2" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="Q3" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="Q4" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="Q5" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="Q6" x="17.78" y="-12.70" length="middle" rot="R180"/>
<pin name="Q7" x="17.78" y="-15.24" length="middle" rot="R180"/>
<pin name="Q8" x="17.78" y="-17.78" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-20.32" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-22.86" length="middle" rot="R180"/>
</symbol>
<symbol name="7474">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="12.7" y1="-20.32" x2="-12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-20.32" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-24.13" size="1.778" layer="96">&gt;VALUE</text>
<pin name="!1CLR" x="-17.78" y="-0.00" length="middle"/>
<pin name="1D" x="-17.78" y="-2.54" length="middle"/>
<pin name="1CLK" x="-17.78" y="-5.08" length="middle"/>
<pin name="!1PRE" x="-17.78" y="-7.62" length="middle"/>
<pin name="!2CLR" x="-17.78" y="-10.16" length="middle"/>
<pin name="2D" x="-17.78" y="-12.70" length="middle"/>
<pin name="2CLK" x="-17.78" y="-15.24" length="middle"/>
<pin name="!2PRE" x="-17.78" y="-17.78" length="middle"/>
<pin name="1Q" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="!1Q" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="2Q" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="!2Q" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-12.70" length="middle" rot="R180"/>
</symbol>
<symbol name="CAP">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="-2.54" x2="-12.7" y2="-2.54" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-2.54" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-6.35" size="1.778" layer="96">&gt;VALUE</text>
<pin name="1" x="-17.78" y="-0.00" length="middle"/>
<pin name="2" x="17.78" y="-0.00" length="middle" rot="R180"/>
</symbol>
<symbol name="DIN96">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-162.56" width="0.254" layer="94"/>
<wire x1="12.7" y1="-162.56" x2="-12.7" y2="-162.56" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-162.56" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-166.37" size="1.778" layer="96">&gt;VALUE</text>
<pin name="A1" x="-17.78" y="-0.00" length="middle"/>
<pin name="A2" x="-17.78" y="-2.54" length="middle"/>
<pin name="A3" x="-17.78" y="-5.08" length="middle"/>
<pin name="A4" x="-17.78" y="-7.62" length="middle"/>
<pin name="A5" x="-17.78" y="-10.16" length="middle"/>
<pin name="A6" x="-17.78" y="-12.70" length="middle"/>
<pin name="A7" x="-17.78" y="-15.24" length="middle"/>
<pin name="A8" x="-17.78" y="-17.78" length="middle"/>
<pin name="A9" x="-17.78" y="-20.32" length="middle"/>
<pin name="A10" x="-17.78" y="-22.86" length="middle"/>
<pin name="A11" x="-17.78" y="-25.40" length="middle"/>
<pin name="A12" x="-17.78" y="-27.94" length="middle"/>
<pin name="A13" x="-17.78" y="-30.48" length="middle"/>
<pin name="A14" x="-17.78" y="-33.02" length="middle"/>
<pin name="A15" x="-17.78" y="-35.56" length="middle"/>
<pin name="A16" x="-17.78" y="-38.10" length="middle"/>
<pin name="A17" x="-17.78" y="-40.64" length="middle"/>
<pin name="A18" x="-17.78" y="-43.18" length="middle"/>
<pin name="A19" x="-17.78" y="-45.72" length="middle"/>
<pin name="A20" x="-17.78" y="-48.26" length="middle"/>
<pin name="A21" x="-17.78" y="-50.80" length="middle"/>
<pin name="A22" x="-17.78" y="-53.34" length="middle"/>
<pin name="A23" x="-17.78" y="-55.88" length="middle"/>
<pin name="A24" x="-17.78" y="-58.42" length="middle"/>
<pin name="A25" x="-17.78" y="-60.96" length="middle"/>
<pin name="A26" x="-17.78" y="-63.50" length="middle"/>
<pin name="A27" x="-17.78" y="-66.04" length="middle"/>
<pin name="A28" x="-17.78" y="-68.58" length="middle"/>
<pin name="A29" x="-17.78" y="-71.12" length="middle"/>
<pin name="A30" x="-17.78" y="-73.66" length="middle"/>
<pin name="A31" x="-17.78" y="-76.20" length="middle"/>
<pin name="A32" x="-17.78" y="-78.74" length="middle"/>
<pin name="B1" x="-17.78" y="-81.28" length="middle"/>
<pin name="B2" x="-17.78" y="-83.82" length="middle"/>
<pin name="B3" x="-17.78" y="-86.36" length="middle"/>
<pin name="B4" x="-17.78" y="-88.90" length="middle"/>
<pin name="B5" x="-17.78" y="-91.44" length="middle"/>
<pin name="B6" x="-17.78" y="-93.98" length="middle"/>
<pin name="B7" x="-17.78" y="-96.52" length="middle"/>
<pin name="B8" x="-17.78" y="-99.06" length="middle"/>
<pin name="B9" x="-17.78" y="-101.60" length="middle"/>
<pin name="B10" x="-17.78" y="-104.14" length="middle"/>
<pin name="B11" x="-17.78" y="-106.68" length="middle"/>
<pin name="B12" x="-17.78" y="-109.22" length="middle"/>
<pin name="B13" x="-17.78" y="-111.76" length="middle"/>
<pin name="B14" x="-17.78" y="-114.30" length="middle"/>
<pin name="B15" x="-17.78" y="-116.84" length="middle"/>
<pin name="B16" x="-17.78" y="-119.38" length="middle"/>
<pin name="B17" x="-17.78" y="-121.92" length="middle"/>
<pin name="B18" x="-17.78" y="-124.46" length="middle"/>
<pin name="B19" x="-17.78" y="-127.00" length="middle"/>
<pin name="B20" x="-17.78" y="-129.54" length="middle"/>
<pin name="B21" x="-17.78" y="-132.08" length="middle"/>
<pin name="B22" x="-17.78" y="-134.62" length="middle"/>
<pin name="B23" x="-17.78" y="-137.16" length="middle"/>
<pin name="B24" x="-17.78" y="-139.70" length="middle"/>
<pin name="B25" x="-17.78" y="-142.24" length="middle"/>
<pin name="B26" x="-17.78" y="-144.78" length="middle"/>
<pin name="B27" x="-17.78" y="-147.32" length="middle"/>
<pin name="B28" x="-17.78" y="-149.86" length="middle"/>
<pin name="B29" x="-17.78" y="-152.40" length="middle"/>
<pin name="B30" x="-17.78" y="-154.94" length="middle"/>
<pin name="B31" x="-17.78" y="-157.48" length="middle"/>
<pin name="B32" x="-17.78" y="-160.02" length="middle"/>
<pin name="C1" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="C2" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="C3" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="C4" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="C5" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="C6" x="17.78" y="-12.70" length="middle" rot="R180"/>
<pin name="C7" x="17.78" y="-15.24" length="middle" rot="R180"/>
<pin name="C8" x="17.78" y="-17.78" length="middle" rot="R180"/>
<pin name="C9" x="17.78" y="-20.32" length="middle" rot="R180"/>
<pin name="C10" x="17.78" y="-22.86" length="middle" rot="R180"/>
<pin name="C11" x="17.78" y="-25.40" length="middle" rot="R180"/>
<pin name="C12" x="17.78" y="-27.94" length="middle" rot="R180"/>
<pin name="C13" x="17.78" y="-30.48" length="middle" rot="R180"/>
<pin name="C14" x="17.78" y="-33.02" length="middle" rot="R180"/>
<pin name="C15" x="17.78" y="-35.56" length="middle" rot="R180"/>
<pin name="C16" x="17.78" y="-38.10" length="middle" rot="R180"/>
<pin name="C17" x="17.78" y="-40.64" length="middle" rot="R180"/>
<pin name="C18" x="17.78" y="-43.18" length="middle" rot="R180"/>
<pin name="C19" x="17.78" y="-45.72" length="middle" rot="R180"/>
<pin name="C20" x="17.78" y="-48.26" length="middle" rot="R180"/>
<pin name="C21" x="17.78" y="-50.80" length="middle" rot="R180"/>
<pin name="C22" x="17.78" y="-53.34" length="middle" rot="R180"/>
<pin name="C23" x="17.78" y="-55.88" length="middle" rot="R180"/>
<pin name="C24" x="17.78" y="-58.42" length="middle" rot="R180"/>
<pin name="C25" x="17.78" y="-60.96" length="middle" rot="R180"/>
<pin name="C26" x="17.78" y="-63.50" length="middle" rot="R180"/>
<pin name="C27" x="17.78" y="-66.04" length="middle" rot="R180"/>
<pin name="C28" x="17.78" y="-68.58" length="middle" rot="R180"/>
<pin name="C29" x="17.78" y="-71.12" length="middle" rot="R180"/>
<pin name="C30" x="17.78" y="-73.66" length="middle" rot="R180"/>
<pin name="C31" x="17.78" y="-76.20" length="middle" rot="R180"/>
<pin name="C32" x="17.78" y="-78.74" length="middle" rot="R180"/>
</symbol>
<symbol name="GATES14">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="12.7" y1="-20.32" x2="-12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-20.32" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-24.13" size="1.778" layer="96">&gt;VALUE</text>
<pin name="1A" x="-17.78" y="-0.00" length="middle"/>
<pin name="1B" x="-17.78" y="-2.54" length="middle"/>
<pin name="2A" x="-17.78" y="-5.08" length="middle"/>
<pin name="2B" x="-17.78" y="-7.62" length="middle"/>
<pin name="3A" x="-17.78" y="-10.16" length="middle"/>
<pin name="3B" x="-17.78" y="-12.70" length="middle"/>
<pin name="4A" x="-17.78" y="-15.24" length="middle"/>
<pin name="4B" x="-17.78" y="-17.78" length="middle"/>
<pin name="1Y" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="2Y" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="3Y" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="4Y" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-12.70" length="middle" rot="R180"/>
</symbol>
<symbol name="HDR4">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-10.16" width="0.254" layer="94"/>
<wire x1="12.7" y1="-10.16" x2="-12.7" y2="-10.16" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-10.16" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-13.97" size="1.778" layer="96">&gt;VALUE</text>
<pin name="1" x="-17.78" y="-0.00" length="middle"/>
<pin name="2" x="-17.78" y="-2.54" length="middle"/>
<pin name="3" x="-17.78" y="-5.08" length="middle"/>
<pin name="4" x="-17.78" y="-7.62" length="middle"/>
</symbol>
<symbol name="HEX14">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="12.7" y1="-20.32" x2="-12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-20.32" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-24.13" size="1.778" layer="96">&gt;VALUE</text>
<pin name="1A" x="-17.78" y="-0.00" length="middle"/>
<pin name="2A" x="-17.78" y="-2.54" length="middle"/>
<pin name="3A" x="-17.78" y="-5.08" length="middle"/>
<pin name="4A" x="-17.78" y="-7.62" length="middle"/>
<pin name="5A" x="-17.78" y="-10.16" length="middle"/>
<pin name="6A" x="-17.78" y="-12.70" length="middle"/>
<pin name="1Y" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="2Y" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="3Y" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="4Y" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="5Y" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="6Y" x="17.78" y="-12.70" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-15.24" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-17.78" length="middle" rot="R180"/>
</symbol>
<symbol name="LED">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="-2.54" x2="-12.7" y2="-2.54" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-2.54" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-6.35" size="1.778" layer="96">&gt;VALUE</text>
<pin name="A" x="-17.78" y="-0.00" length="middle"/>
<pin name="K" x="17.78" y="-0.00" length="middle" rot="R180"/>
</symbol>
<symbol name="OSC">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-7.62" width="0.254" layer="94"/>
<wire x1="12.7" y1="-7.62" x2="-12.7" y2="-7.62" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-7.62" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-11.43" size="1.778" layer="96">&gt;VALUE</text>
<pin name="NC1" x="-17.78" y="-0.00" length="middle"/>
<pin name="OUT" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-5.08" length="middle" rot="R180"/>
</symbol>
<symbol name="RES">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="-2.54" x2="-12.7" y2="-2.54" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-2.54" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-6.35" size="1.778" layer="96">&gt;VALUE</text>
<pin name="1" x="-17.78" y="-0.00" length="middle"/>
<pin name="2" x="17.78" y="-0.00" length="middle" rot="R180"/>
</symbol>
<symbol name="SW2">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="-2.54" x2="-12.7" y2="-2.54" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-2.54" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-6.35" size="1.778" layer="96">&gt;VALUE</text>
<pin name="1" x="-17.78" y="-0.00" length="middle"/>
<pin name="2" x="17.78" y="-0.00" length="middle" rot="R180"/>
</symbol>
</symbols>
<devicesets>
<deviceset name="28C64" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="28C64" x="0" y="0"/></gates>
<devices><device name="" package="DIP28W"><connects>
<connect gate="G$1" pin="RDY" pad="1"/>
<connect gate="G$1" pin="A12" pad="2"/>
<connect gate="G$1" pin="A7" pad="3"/>
<connect gate="G$1" pin="A6" pad="4"/>
<connect gate="G$1" pin="A5" pad="5"/>
<connect gate="G$1" pin="A4" pad="6"/>
<connect gate="G$1" pin="A3" pad="7"/>
<connect gate="G$1" pin="A2" pad="8"/>
<connect gate="G$1" pin="A1" pad="9"/>
<connect gate="G$1" pin="A0" pad="10"/>
<connect gate="G$1" pin="IO0" pad="11"/>
<connect gate="G$1" pin="IO1" pad="12"/>
<connect gate="G$1" pin="IO2" pad="13"/>
<connect gate="G$1" pin="GND" pad="14"/>
<connect gate="G$1" pin="IO3" pad="15"/>
<connect gate="G$1" pin="IO4" pad="16"/>
<connect gate="G$1" pin="IO5" pad="17"/>
<connect gate="G$1" pin="IO6" pad="18"/>
<connect gate="G$1" pin="IO7" pad="19"/>
<connect gate="G$1" pin="!CE" pad="20"/>
<connect gate="G$1" pin="A10" pad="21"/>
<connect gate="G$1" pin="!OE" pad="22"/>
<connect gate="G$1" pin="A11" pad="23"/>
<connect gate="G$1" pin="A9" pad="24"/>
<connect gate="G$1" pin="A8" pad="25"/>
<connect gate="G$1" pin="NC26" pad="26"/>
<connect gate="G$1" pin="!WE" pad="27"/>
<connect gate="G$1" pin="VCC" pad="28"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="74138" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="74138" x="0" y="0"/></gates>
<devices><device name="" package="DIP16"><connects>
<connect gate="G$1" pin="A" pad="1"/>
<connect gate="G$1" pin="B" pad="2"/>
<connect gate="G$1" pin="C" pad="3"/>
<connect gate="G$1" pin="!G2A" pad="4"/>
<connect gate="G$1" pin="!G2B" pad="5"/>
<connect gate="G$1" pin="G1" pad="6"/>
<connect gate="G$1" pin="Y7" pad="7"/>
<connect gate="G$1" pin="GND" pad="8"/>
<connect gate="G$1" pin="Y6" pad="9"/>
<connect gate="G$1" pin="Y5" pad="10"/>
<connect gate="G$1" pin="Y4" pad="11"/>
<connect gate="G$1" pin="Y3" pad="12"/>
<connect gate="G$1" pin="Y2" pad="13"/>
<connect gate="G$1" pin="Y1" pad="14"/>
<connect gate="G$1" pin="Y0" pad="15"/>
<connect gate="G$1" pin="VCC" pad="16"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="74151" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="74151" x="0" y="0"/></gates>
<devices><device name="" package="DIP16"><connects>
<connect gate="G$1" pin="D3" pad="1"/>
<connect gate="G$1" pin="D2" pad="2"/>
<connect gate="G$1" pin="D1" pad="3"/>
<connect gate="G$1" pin="D0" pad="4"/>
<connect gate="G$1" pin="Y" pad="5"/>
<connect gate="G$1" pin="!W" pad="6"/>
<connect gate="G$1" pin="!G" pad="7"/>
<connect gate="G$1" pin="GND" pad="8"/>
<connect gate="G$1" pin="C" pad="9"/>
<connect gate="G$1" pin="B" pad="10"/>
<connect gate="G$1" pin="A" pad="11"/>
<connect gate="G$1" pin="D7" pad="12"/>
<connect gate="G$1" pin="D6" pad="13"/>
<connect gate="G$1" pin="D5" pad="14"/>
<connect gate="G$1" pin="D4" pad="15"/>
<connect gate="G$1" pin="VCC" pad="16"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="74161" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="74161" x="0" y="0"/></gates>
<devices><device name="" package="DIP16"><connects>
<connect gate="G$1" pin="!CLR" pad="1"/>
<connect gate="G$1" pin="CLK" pad="2"/>
<connect gate="G$1" pin="A" pad="3"/>
<connect gate="G$1" pin="B" pad="4"/>
<connect gate="G$1" pin="C" pad="5"/>
<connect gate="G$1" pin="D" pad="6"/>
<connect gate="G$1" pin="ENP" pad="7"/>
<connect gate="G$1" pin="GND" pad="8"/>
<connect gate="G$1" pin="!LOAD" pad="9"/>
<connect gate="G$1" pin="ENT" pad="10"/>
<connect gate="G$1" pin="QD" pad="11"/>
<connect gate="G$1" pin="QC" pad="12"/>
<connect gate="G$1" pin="QB" pad="13"/>
<connect gate="G$1" pin="QA" pad="14"/>
<connect gate="G$1" pin="RCO" pad="15"/>
<connect gate="G$1" pin="VCC" pad="16"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="74244" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="74244" x="0" y="0"/></gates>
<devices><device name="" package="DIP20"><connects>
<connect gate="G$1" pin="!G1" pad="1"/>
<connect gate="G$1" pin="A1" pad="2"/>
<connect gate="G$1" pin="Y8" pad="3"/>
<connect gate="G$1" pin="A2" pad="4"/>
<connect gate="G$1" pin="Y7" pad="5"/>
<connect gate="G$1" pin="A3" pad="6"/>
<connect gate="G$1" pin="Y6" pad="7"/>
<connect gate="G$1" pin="A4" pad="8"/>
<connect gate="G$1" pin="Y5" pad="9"/>
<connect gate="G$1" pin="GND" pad="10"/>
<connect gate="G$1" pin="A5" pad="11"/>
<connect gate="G$1" pin="Y4" pad="12"/>
<connect gate="G$1" pin="A6" pad="13"/>
<connect gate="G$1" pin="Y3" pad="14"/>
<connect gate="G$1" pin="A7" pad="15"/>
<connect gate="G$1" pin="Y2" pad="16"/>
<connect gate="G$1" pin="A8" pad="17"/>
<connect gate="G$1" pin="Y1" pad="18"/>
<connect gate="G$1" pin="!G2" pad="19"/>
<connect gate="G$1" pin="VCC" pad="20"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="74374" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="74374" x="0" y="0"/></gates>
<devices><device name="" package="DIP20"><connects>
<connect gate="G$1" pin="!OC" pad="1"/>
<connect gate="G$1" pin="Q1" pad="2"/>
<connect gate="G$1" pin="D1" pad="3"/>
<connect gate="G$1" pin="D2" pad="4"/>
<connect gate="G$1" pin="Q2" pad="5"/>
<connect gate="G$1" pin="Q3" pad="6"/>
<connect gate="G$1" pin="D3" pad="7"/>
<connect gate="G$1" pin="D4" pad="8"/>
<connect gate="G$1" pin="Q4" pad="9"/>
<connect gate="G$1" pin="GND" pad="10"/>
<connect gate="G$1" pin="CLK" pad="11"/>
<connect gate="G$1" pin="Q5" pad="12"/>
<connect gate="G$1" pin="D5" pad="13"/>
<connect gate="G$1" pin="D6" pad="14"/>
<connect gate="G$1" pin="Q6" pad="15"/>
<connect gate="G$1" pin="Q7" pad="16"/>
<connect gate="G$1" pin="D7" pad="17"/>
<connect gate="G$1" pin="D8" pad="18"/>
<connect gate="G$1" pin="Q8" pad="19"/>
<connect gate="G$1" pin="VCC" pad="20"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="74377V2" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="74377V2" x="0" y="0"/></gates>
<devices><device name="" package="DIP20"><connects>
<connect gate="G$1" pin="Q1" pad="2"/>
<connect gate="G$1" pin="D1" pad="3"/>
<connect gate="G$1" pin="D2" pad="4"/>
<connect gate="G$1" pin="Q2" pad="5"/>
<connect gate="G$1" pin="Q3" pad="6"/>
<connect gate="G$1" pin="D3" pad="7"/>
<connect gate="G$1" pin="D4" pad="8"/>
<connect gate="G$1" pin="Q4" pad="9"/>
<connect gate="G$1" pin="GND" pad="10"/>
<connect gate="G$1" pin="CLK" pad="11"/>
<connect gate="G$1" pin="Q5" pad="12"/>
<connect gate="G$1" pin="D5" pad="13"/>
<connect gate="G$1" pin="D6" pad="14"/>
<connect gate="G$1" pin="Q6" pad="15"/>
<connect gate="G$1" pin="Q7" pad="16"/>
<connect gate="G$1" pin="D7" pad="17"/>
<connect gate="G$1" pin="D8" pad="18"/>
<connect gate="G$1" pin="Q8" pad="19"/>
<connect gate="G$1" pin="VCC" pad="20"/>
<connect gate="G$1" pin="!E" pad="1"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="7474" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="7474" x="0" y="0"/></gates>
<devices><device name="" package="DIP14"><connects>
<connect gate="G$1" pin="!1CLR" pad="1"/>
<connect gate="G$1" pin="1D" pad="2"/>
<connect gate="G$1" pin="1CLK" pad="3"/>
<connect gate="G$1" pin="!1PRE" pad="4"/>
<connect gate="G$1" pin="1Q" pad="5"/>
<connect gate="G$1" pin="!1Q" pad="6"/>
<connect gate="G$1" pin="GND" pad="7"/>
<connect gate="G$1" pin="!2Q" pad="8"/>
<connect gate="G$1" pin="2Q" pad="9"/>
<connect gate="G$1" pin="!2PRE" pad="10"/>
<connect gate="G$1" pin="2CLK" pad="11"/>
<connect gate="G$1" pin="2D" pad="12"/>
<connect gate="G$1" pin="!2CLR" pad="13"/>
<connect gate="G$1" pin="VCC" pad="14"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="CAP" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="CAP" x="0" y="0"/></gates>
<devices><device name="" package="C_DISC"><connects>
<connect gate="G$1" pin="1" pad="1"/>
<connect gate="G$1" pin="2" pad="2"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="DIN96" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="DIN96" x="0" y="0"/></gates>
<devices><device name="" package="DIN96"><connects>
<connect gate="G$1" pin="A1" pad="A1"/>
<connect gate="G$1" pin="A2" pad="A2"/>
<connect gate="G$1" pin="A3" pad="A3"/>
<connect gate="G$1" pin="A4" pad="A4"/>
<connect gate="G$1" pin="A5" pad="A5"/>
<connect gate="G$1" pin="A6" pad="A6"/>
<connect gate="G$1" pin="A7" pad="A7"/>
<connect gate="G$1" pin="A8" pad="A8"/>
<connect gate="G$1" pin="A9" pad="A9"/>
<connect gate="G$1" pin="A10" pad="A10"/>
<connect gate="G$1" pin="A11" pad="A11"/>
<connect gate="G$1" pin="A12" pad="A12"/>
<connect gate="G$1" pin="A13" pad="A13"/>
<connect gate="G$1" pin="A14" pad="A14"/>
<connect gate="G$1" pin="A15" pad="A15"/>
<connect gate="G$1" pin="A16" pad="A16"/>
<connect gate="G$1" pin="A17" pad="A17"/>
<connect gate="G$1" pin="A18" pad="A18"/>
<connect gate="G$1" pin="A19" pad="A19"/>
<connect gate="G$1" pin="A20" pad="A20"/>
<connect gate="G$1" pin="A21" pad="A21"/>
<connect gate="G$1" pin="A22" pad="A22"/>
<connect gate="G$1" pin="A23" pad="A23"/>
<connect gate="G$1" pin="A24" pad="A24"/>
<connect gate="G$1" pin="A25" pad="A25"/>
<connect gate="G$1" pin="A26" pad="A26"/>
<connect gate="G$1" pin="A27" pad="A27"/>
<connect gate="G$1" pin="A28" pad="A28"/>
<connect gate="G$1" pin="A29" pad="A29"/>
<connect gate="G$1" pin="A30" pad="A30"/>
<connect gate="G$1" pin="A31" pad="A31"/>
<connect gate="G$1" pin="A32" pad="A32"/>
<connect gate="G$1" pin="B1" pad="B1"/>
<connect gate="G$1" pin="B2" pad="B2"/>
<connect gate="G$1" pin="B3" pad="B3"/>
<connect gate="G$1" pin="B4" pad="B4"/>
<connect gate="G$1" pin="B5" pad="B5"/>
<connect gate="G$1" pin="B6" pad="B6"/>
<connect gate="G$1" pin="B7" pad="B7"/>
<connect gate="G$1" pin="B8" pad="B8"/>
<connect gate="G$1" pin="B9" pad="B9"/>
<connect gate="G$1" pin="B10" pad="B10"/>
<connect gate="G$1" pin="B11" pad="B11"/>
<connect gate="G$1" pin="B12" pad="B12"/>
<connect gate="G$1" pin="B13" pad="B13"/>
<connect gate="G$1" pin="B14" pad="B14"/>
<connect gate="G$1" pin="B15" pad="B15"/>
<connect gate="G$1" pin="B16" pad="B16"/>
<connect gate="G$1" pin="B17" pad="B17"/>
<connect gate="G$1" pin="B18" pad="B18"/>
<connect gate="G$1" pin="B19" pad="B19"/>
<connect gate="G$1" pin="B20" pad="B20"/>
<connect gate="G$1" pin="B21" pad="B21"/>
<connect gate="G$1" pin="B22" pad="B22"/>
<connect gate="G$1" pin="B23" pad="B23"/>
<connect gate="G$1" pin="B24" pad="B24"/>
<connect gate="G$1" pin="B25" pad="B25"/>
<connect gate="G$1" pin="B26" pad="B26"/>
<connect gate="G$1" pin="B27" pad="B27"/>
<connect gate="G$1" pin="B28" pad="B28"/>
<connect gate="G$1" pin="B29" pad="B29"/>
<connect gate="G$1" pin="B30" pad="B30"/>
<connect gate="G$1" pin="B31" pad="B31"/>
<connect gate="G$1" pin="B32" pad="B32"/>
<connect gate="G$1" pin="C1" pad="C1"/>
<connect gate="G$1" pin="C2" pad="C2"/>
<connect gate="G$1" pin="C3" pad="C3"/>
<connect gate="G$1" pin="C4" pad="C4"/>
<connect gate="G$1" pin="C5" pad="C5"/>
<connect gate="G$1" pin="C6" pad="C6"/>
<connect gate="G$1" pin="C7" pad="C7"/>
<connect gate="G$1" pin="C8" pad="C8"/>
<connect gate="G$1" pin="C9" pad="C9"/>
<connect gate="G$1" pin="C10" pad="C10"/>
<connect gate="G$1" pin="C11" pad="C11"/>
<connect gate="G$1" pin="C12" pad="C12"/>
<connect gate="G$1" pin="C13" pad="C13"/>
<connect gate="G$1" pin="C14" pad="C14"/>
<connect gate="G$1" pin="C15" pad="C15"/>
<connect gate="G$1" pin="C16" pad="C16"/>
<connect gate="G$1" pin="C17" pad="C17"/>
<connect gate="G$1" pin="C18" pad="C18"/>
<connect gate="G$1" pin="C19" pad="C19"/>
<connect gate="G$1" pin="C20" pad="C20"/>
<connect gate="G$1" pin="C21" pad="C21"/>
<connect gate="G$1" pin="C22" pad="C22"/>
<connect gate="G$1" pin="C23" pad="C23"/>
<connect gate="G$1" pin="C24" pad="C24"/>
<connect gate="G$1" pin="C25" pad="C25"/>
<connect gate="G$1" pin="C26" pad="C26"/>
<connect gate="G$1" pin="C27" pad="C27"/>
<connect gate="G$1" pin="C28" pad="C28"/>
<connect gate="G$1" pin="C29" pad="C29"/>
<connect gate="G$1" pin="C30" pad="C30"/>
<connect gate="G$1" pin="C31" pad="C31"/>
<connect gate="G$1" pin="C32" pad="C32"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="GATES14" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="GATES14" x="0" y="0"/></gates>
<devices><device name="" package="DIP14"><connects>
<connect gate="G$1" pin="1A" pad="1"/>
<connect gate="G$1" pin="1B" pad="2"/>
<connect gate="G$1" pin="1Y" pad="3"/>
<connect gate="G$1" pin="2A" pad="4"/>
<connect gate="G$1" pin="2B" pad="5"/>
<connect gate="G$1" pin="2Y" pad="6"/>
<connect gate="G$1" pin="GND" pad="7"/>
<connect gate="G$1" pin="3Y" pad="8"/>
<connect gate="G$1" pin="3A" pad="9"/>
<connect gate="G$1" pin="3B" pad="10"/>
<connect gate="G$1" pin="4Y" pad="11"/>
<connect gate="G$1" pin="4A" pad="12"/>
<connect gate="G$1" pin="4B" pad="13"/>
<connect gate="G$1" pin="VCC" pad="14"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="HDR4" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="HDR4" x="0" y="0"/></gates>
<devices><device name="" package="HDR4"><connects>
<connect gate="G$1" pin="1" pad="1"/>
<connect gate="G$1" pin="2" pad="2"/>
<connect gate="G$1" pin="3" pad="3"/>
<connect gate="G$1" pin="4" pad="4"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="HEX14" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="HEX14" x="0" y="0"/></gates>
<devices><device name="" package="DIP14"><connects>
<connect gate="G$1" pin="1A" pad="1"/>
<connect gate="G$1" pin="1Y" pad="2"/>
<connect gate="G$1" pin="2A" pad="3"/>
<connect gate="G$1" pin="2Y" pad="4"/>
<connect gate="G$1" pin="3A" pad="5"/>
<connect gate="G$1" pin="3Y" pad="6"/>
<connect gate="G$1" pin="GND" pad="7"/>
<connect gate="G$1" pin="4Y" pad="8"/>
<connect gate="G$1" pin="4A" pad="9"/>
<connect gate="G$1" pin="5Y" pad="10"/>
<connect gate="G$1" pin="5A" pad="11"/>
<connect gate="G$1" pin="6Y" pad="12"/>
<connect gate="G$1" pin="6A" pad="13"/>
<connect gate="G$1" pin="VCC" pad="14"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="LED" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="LED" x="0" y="0"/></gates>
<devices><device name="" package="LED5"><connects>
<connect gate="G$1" pin="A" pad="2"/>
<connect gate="G$1" pin="K" pad="1"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="OSC" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="OSC" x="0" y="0"/></gates>
<devices><device name="" package="OSC4"><connects>
<connect gate="G$1" pin="NC1" pad="1"/>
<connect gate="G$1" pin="GND" pad="7"/>
<connect gate="G$1" pin="OUT" pad="8"/>
<connect gate="G$1" pin="VCC" pad="14"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="RES" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="RES" x="0" y="0"/></gates>
<devices><device name="" package="R_AXIAL"><connects>
<connect gate="G$1" pin="1" pad="1"/>
<connect gate="G$1" pin="2" pad="2"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="SW2" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="SW2" x="0" y="0"/></gates>
<devices><device name="" package="SW2P"><connects>
<connect gate="G$1" pin="1" pad="1"/>
<connect gate="G$1" pin="2" pad="2"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
</devicesets>
</library></libraries>
<classes><class number="0" name="default" width="0" drill="0"/></classes>
<parts>
<part name="J1" library="p8x" deviceset="DIN96" device="" value="FABC96R"/>
<part name="U1" library="p8x" deviceset="74161" device="" value="CLK DIV"/>
<part name="U2" library="p8x" deviceset="HEX14" device="" value="74HCT14"/>
<part name="U3" library="p8x" deviceset="7474" device="" value="74HCT74"/>
<part name="U4" library="p8x" deviceset="GATES14" device="" value="74HCT00"/>
<part name="U5" library="p8x" deviceset="GATES14" device="" value="74HCT08"/>
<part name="U6" library="p8x" deviceset="GATES14" device="" value="74HCT32"/>
<part name="U7" library="p8x" deviceset="74377V2" device="" value="IR 74HCT377"/>
<part name="U8" library="p8x" deviceset="74138" device="" value="DLD DEC"/>
<part name="U9" library="p8x" deviceset="74151" device="" value="COND MUX"/>
<part name="U10" library="p8x" deviceset="28C64" device="" value="UCODE ROM0"/>
<part name="U11" library="p8x" deviceset="28C64" device="" value="UCODE ROM1"/>
<part name="U12" library="p8x" deviceset="28C64" device="" value="UCODE ROM2"/>
<part name="U13" library="p8x" deviceset="28C64" device="" value="UCODE ROM3"/>
<part name="U14" library="p8x" deviceset="74374" device="" value="PIPE0"/>
<part name="U15" library="p8x" deviceset="74374" device="" value="PIPE1"/>
<part name="U16" library="p8x" deviceset="74374" device="" value="PIPE2"/>
<part name="U17" library="p8x" deviceset="74374" device="" value="PIPE3"/>
<part name="U18" library="p8x" deviceset="74161" device="" value="STEP CNT"/>
<part name="U19" library="p8x" deviceset="GATES14" device="" value="74HCT86 NV-XOR"/>
<part name="U20" library="p8x" deviceset="74244" device="" value="IRQ-FORCE DNP"/>
<part name="U21" library="p8x" deviceset="7474" device="" value="IRQ/IE FF DNP"/>
<part name="X1" library="p8x" deviceset="OSC" device="" value="4MHZ"/>
<part name="JP1" library="p8x" deviceset="HDR4" device="" value="CLKSEL"/>
<part name="SWR" library="p8x" deviceset="SW2" device="" value="RUN/HALT"/>
<part name="SWS" library="p8x" deviceset="SW2" device="" value="STEP"/>
<part name="SWT" library="p8x" deviceset="SW2" device="" value="RESET"/>
<part name="R1" library="p8x" deviceset="RES" device="" value="10K"/>
<part name="R2" library="p8x" deviceset="RES" device="" value="10K"/>
<part name="R3" library="p8x" deviceset="RES" device="" value="10K"/>
<part name="C1" library="p8x" deviceset="CAP" device="" value="1U"/>
<part name="RP1" library="p8x" deviceset="RES" device="" value="1K"/>
<part name="LED3" library="p8x" deviceset="LED" device="" value="PWR-GRN"/>
<part name="R4" library="p8x" deviceset="RES" device="" value="1K"/>
<part name="LED4" library="p8x" deviceset="LED" device="" value="RUN-GRN"/>
<part name="R5" library="p8x" deviceset="RES" device="" value="1K"/>
<part name="LED5" library="p8x" deviceset="LED" device="" value="HALT-RED"/>
<part name="CD1" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD2" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD3" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD4" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD5" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD6" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD7" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD8" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD9" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD10" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD11" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD12" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD13" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD14" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD15" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD16" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD17" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD18" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD19" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD20" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD21" library="p8x" deviceset="CAP" device="" value="100N"/>
</parts><sheets><sheet><plain>
<text x="0" y="40" size="3.81" layer="97">P8X CONTROL/MICROCODE CARD REV B</text>
</plain><instances>
<instance part="J1" gate="G$1" x="0" y="38.1"/>
<instance part="U1" gate="G$1" x="140.0" y="38.1"/>
<instance part="U2" gate="G$1" x="241.6" y="38.1"/>
<instance part="U3" gate="G$1" x="343.2" y="38.1"/>
<instance part="U4" gate="G$1" x="444.79999999999995" y="38.1"/>
<instance part="U5" gate="G$1" x="140.0" y="-101.6"/>
<instance part="U6" gate="G$1" x="241.6" y="-101.6"/>
<instance part="U7" gate="G$1" x="343.2" y="-101.6"/>
<instance part="U8" gate="G$1" x="444.79999999999995" y="-101.6"/>
<instance part="U9" gate="G$1" x="140.0" y="-241.29999999999998"/>
<instance part="U10" gate="G$1" x="241.6" y="-241.29999999999998"/>
<instance part="U11" gate="G$1" x="343.2" y="-241.29999999999998"/>
<instance part="U12" gate="G$1" x="444.79999999999995" y="-241.29999999999998"/>
<instance part="U13" gate="G$1" x="140.0" y="-380.99999999999994"/>
<instance part="U14" gate="G$1" x="241.6" y="-380.99999999999994"/>
<instance part="U15" gate="G$1" x="343.2" y="-380.99999999999994"/>
<instance part="U16" gate="G$1" x="444.79999999999995" y="-380.99999999999994"/>
<instance part="U17" gate="G$1" x="140.0" y="-520.6999999999999"/>
<instance part="U18" gate="G$1" x="241.6" y="-520.6999999999999"/>
<instance part="U19" gate="G$1" x="343.2" y="-520.6999999999999"/>
<instance part="U20" gate="G$1" x="444.79999999999995" y="-520.6999999999999"/>
<instance part="U21" gate="G$1" x="140.0" y="-660.4"/>
<instance part="X1" gate="G$1" x="241.6" y="-660.4"/>
<instance part="JP1" gate="G$1" x="343.2" y="-660.4"/>
<instance part="SWR" gate="G$1" x="444.79999999999995" y="-660.4"/>
<instance part="SWS" gate="G$1" x="140.0" y="-800.0999999999999"/>
<instance part="SWT" gate="G$1" x="241.6" y="-800.0999999999999"/>
<instance part="R1" gate="G$1" x="343.2" y="-800.0999999999999"/>
<instance part="R2" gate="G$1" x="444.79999999999995" y="-800.0999999999999"/>
<instance part="R3" gate="G$1" x="140.0" y="-939.7999999999998"/>
<instance part="C1" gate="G$1" x="241.6" y="-939.7999999999998"/>
<instance part="RP1" gate="G$1" x="343.2" y="-939.7999999999998"/>
<instance part="LED3" gate="G$1" x="444.79999999999995" y="-939.7999999999998"/>
<instance part="R4" gate="G$1" x="140.0" y="-1079.5"/>
<instance part="LED4" gate="G$1" x="241.6" y="-1079.5"/>
<instance part="R5" gate="G$1" x="343.2" y="-1079.5"/>
<instance part="LED5" gate="G$1" x="444.79999999999995" y="-1079.5"/>
<instance part="CD1" gate="G$1" x="140.0" y="-1219.2"/>
<instance part="CD2" gate="G$1" x="241.6" y="-1219.2"/>
<instance part="CD3" gate="G$1" x="343.2" y="-1219.2"/>
<instance part="CD4" gate="G$1" x="444.79999999999995" y="-1219.2"/>
<instance part="CD5" gate="G$1" x="140.0" y="-1358.9"/>
<instance part="CD6" gate="G$1" x="241.6" y="-1358.9"/>
<instance part="CD7" gate="G$1" x="343.2" y="-1358.9"/>
<instance part="CD8" gate="G$1" x="444.79999999999995" y="-1358.9"/>
<instance part="CD9" gate="G$1" x="140.0" y="-1498.6"/>
<instance part="CD10" gate="G$1" x="241.6" y="-1498.6"/>
<instance part="CD11" gate="G$1" x="343.2" y="-1498.6"/>
<instance part="CD12" gate="G$1" x="444.79999999999995" y="-1498.6"/>
<instance part="CD13" gate="G$1" x="140.0" y="-1638.3"/>
<instance part="CD14" gate="G$1" x="241.6" y="-1638.3"/>
<instance part="CD15" gate="G$1" x="343.2" y="-1638.3"/>
<instance part="CD16" gate="G$1" x="444.79999999999995" y="-1638.3"/>
<instance part="CD17" gate="G$1" x="140.0" y="-1778.0"/>
<instance part="CD18" gate="G$1" x="241.6" y="-1778.0"/>
<instance part="CD19" gate="G$1" x="343.2" y="-1778.0"/>
<instance part="CD20" gate="G$1" x="444.79999999999995" y="-1778.0"/>
<instance part="CD21" gate="G$1" x="140.0" y="-1917.6999999999998"/>
</instances><busses/><nets>
<net name="OSCO" class="0">
<segment><pinref part="X1" gate="G$1" pin="OUT"/>
<wire x1="259.38" y1="-660.40" x2="264.46" y2="-660.40" width="0.1524" layer="91"/>
<label x="264.46" y="-659.89" size="1.778" layer="95"/></segment>
<segment><pinref part="JP1" gate="G$1" pin="1"/>
<wire x1="325.42" y1="-660.40" x2="320.34" y2="-660.40" width="0.1524" layer="91"/>
<label x="320.34" y="-659.89" size="1.778" layer="95"/></segment>
<segment><pinref part="U1" gate="G$1" pin="CLK"/>
<wire x1="122.22" y1="35.56" x2="117.14" y2="35.56" width="0.1524" layer="91"/>
<label x="117.14" y="36.07" size="1.778" layer="95"/></segment>
</net>
<net name="DIVQA" class="0">
<segment><pinref part="U1" gate="G$1" pin="QA"/>
<wire x1="157.78" y1="38.10" x2="162.86" y2="38.10" width="0.1524" layer="91"/>
<label x="162.86" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="JP1" gate="G$1" pin="3"/>
<wire x1="325.42" y1="-665.48" x2="320.34" y2="-665.48" width="0.1524" layer="91"/>
<label x="320.34" y="-664.97" size="1.778" layer="95"/></segment>
</net>
<net name="DIVQB" class="0">
<segment><pinref part="U1" gate="G$1" pin="QB"/>
<wire x1="157.78" y1="35.56" x2="162.86" y2="35.56" width="0.1524" layer="91"/>
<label x="162.86" y="36.07" size="1.778" layer="95"/></segment>
<segment><pinref part="JP1" gate="G$1" pin="4"/>
<wire x1="325.42" y1="-668.02" x2="320.34" y2="-668.02" width="0.1524" layer="91"/>
<label x="320.34" y="-667.51" size="1.778" layer="95"/></segment>
</net>
<net name="CLKRAW" class="0">
<segment><pinref part="JP1" gate="G$1" pin="2"/>
<wire x1="325.42" y1="-662.94" x2="320.34" y2="-662.94" width="0.1524" layer="91"/>
<label x="320.34" y="-662.43" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="1CLK"/>
<wire x1="325.42" y1="33.02" x2="320.34" y2="33.02" width="0.1524" layer="91"/>
<label x="320.34" y="33.53" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="2CLK"/>
<wire x1="325.42" y1="22.86" x2="320.34" y2="22.86" width="0.1524" layer="91"/>
<label x="320.34" y="23.37" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="1A"/>
<wire x1="122.22" y1="-101.60" x2="117.14" y2="-101.60" width="0.1524" layer="91"/>
<label x="117.14" y="-101.09" size="1.778" layer="95"/></segment>
</net>
<net name="VCC" class="0">
<segment><pinref part="U1" gate="G$1" pin="ENP"/>
<wire x1="122.22" y1="22.86" x2="117.14" y2="22.86" width="0.1524" layer="91"/>
<label x="117.14" y="23.37" size="1.778" layer="95"/></segment>
<segment><pinref part="U1" gate="G$1" pin="ENT"/>
<wire x1="122.22" y1="17.78" x2="117.14" y2="17.78" width="0.1524" layer="91"/>
<label x="117.14" y="18.29" size="1.778" layer="95"/></segment>
<segment><pinref part="U1" gate="G$1" pin="!LOAD"/>
<wire x1="122.22" y1="20.32" x2="117.14" y2="20.32" width="0.1524" layer="91"/>
<label x="117.14" y="20.83" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="!1PRE"/>
<wire x1="325.42" y1="30.48" x2="320.34" y2="30.48" width="0.1524" layer="91"/>
<label x="320.34" y="30.99" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="!2PRE"/>
<wire x1="325.42" y1="20.32" x2="320.34" y2="20.32" width="0.1524" layer="91"/>
<label x="320.34" y="20.83" size="1.778" layer="95"/></segment>
<segment><pinref part="U18" gate="G$1" pin="ENP"/>
<wire x1="223.82" y1="-535.94" x2="218.74" y2="-535.94" width="0.1524" layer="91"/>
<label x="218.74" y="-535.43" size="1.778" layer="95"/></segment>
<segment><pinref part="U18" gate="G$1" pin="ENT"/>
<wire x1="223.82" y1="-541.02" x2="218.74" y2="-541.02" width="0.1524" layer="91"/>
<label x="218.74" y="-540.51" size="1.778" layer="95"/></segment>
<segment><pinref part="R1" gate="G$1" pin="1"/>
<wire x1="325.42" y1="-800.10" x2="320.34" y2="-800.10" width="0.1524" layer="91"/>
<label x="320.34" y="-799.59" size="1.778" layer="95"/></segment>
<segment><pinref part="R2" gate="G$1" pin="1"/>
<wire x1="427.02" y1="-800.10" x2="421.94" y2="-800.10" width="0.1524" layer="91"/>
<label x="421.94" y="-799.59" size="1.778" layer="95"/></segment>
<segment><pinref part="R3" gate="G$1" pin="1"/>
<wire x1="122.22" y1="-939.80" x2="117.14" y2="-939.80" width="0.1524" layer="91"/>
<label x="117.14" y="-939.29" size="1.778" layer="95"/></segment>
<segment><pinref part="X1" gate="G$1" pin="VCC"/>
<wire x1="259.38" y1="-662.94" x2="264.46" y2="-662.94" width="0.1524" layer="91"/>
<label x="264.46" y="-662.43" size="1.778" layer="95"/></segment>
<segment><pinref part="U8" gate="G$1" pin="G1"/>
<wire x1="427.02" y1="-109.22" x2="421.94" y2="-109.22" width="0.1524" layer="91"/>
<label x="421.94" y="-108.71" size="1.778" layer="95"/></segment>
<segment><pinref part="RP1" gate="G$1" pin="1"/>
<wire x1="325.42" y1="-939.80" x2="320.34" y2="-939.80" width="0.1524" layer="91"/>
<label x="320.34" y="-939.29" size="1.778" layer="95"/></segment>
<segment><pinref part="R4" gate="G$1" pin="1"/>
<wire x1="122.22" y1="-1079.50" x2="117.14" y2="-1079.50" width="0.1524" layer="91"/>
<label x="117.14" y="-1078.99" size="1.778" layer="95"/></segment>
<segment><pinref part="R5" gate="G$1" pin="1"/>
<wire x1="325.42" y1="-1079.50" x2="320.34" y2="-1079.50" width="0.1524" layer="91"/>
<label x="320.34" y="-1078.99" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="!WE"/>
<wire x1="259.38" y1="-266.70" x2="264.46" y2="-266.70" width="0.1524" layer="91"/>
<label x="264.46" y="-266.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="!WE"/>
<wire x1="360.98" y1="-266.70" x2="366.06" y2="-266.70" width="0.1524" layer="91"/>
<label x="366.06" y="-266.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="!WE"/>
<wire x1="462.58" y1="-266.70" x2="467.66" y2="-266.70" width="0.1524" layer="91"/>
<label x="467.66" y="-266.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="!WE"/>
<wire x1="157.78" y1="-406.40" x2="162.86" y2="-406.40" width="0.1524" layer="91"/>
<label x="162.86" y="-405.89" size="1.778" layer="95"/></segment>
<segment><pinref part="U9" gate="G$1" pin="D1"/>
<wire x1="122.22" y1="-251.46" x2="117.14" y2="-251.46" width="0.1524" layer="91"/>
<label x="117.14" y="-250.95" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="!G1"/>
<wire x1="427.02" y1="-520.70" x2="421.94" y2="-520.70" width="0.1524" layer="91"/>
<label x="421.94" y="-520.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="!G2"/>
<wire x1="427.02" y1="-533.40" x2="421.94" y2="-533.40" width="0.1524" layer="91"/>
<label x="421.94" y="-532.89" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="A4"/>
<wire x1="427.02" y1="-530.86" x2="421.94" y2="-530.86" width="0.1524" layer="91"/>
<label x="421.94" y="-530.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U21" gate="G$1" pin="!1PRE"/>
<wire x1="122.22" y1="-668.02" x2="117.14" y2="-668.02" width="0.1524" layer="91"/>
<label x="117.14" y="-667.51" size="1.778" layer="95"/></segment>
<segment><pinref part="U21" gate="G$1" pin="!2PRE"/>
<wire x1="122.22" y1="-678.18" x2="117.14" y2="-678.18" width="0.1524" layer="91"/>
<label x="117.14" y="-677.67" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A1"/>
<wire x1="-17.78" y1="38.10" x2="-22.86" y2="38.10" width="0.1524" layer="91"/>
<label x="-22.86" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A2"/>
<wire x1="-17.78" y1="35.56" x2="-22.86" y2="35.56" width="0.1524" layer="91"/>
<label x="-22.86" y="36.07" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B1"/>
<wire x1="-17.78" y1="-43.18" x2="-22.86" y2="-43.18" width="0.1524" layer="91"/>
<label x="-22.86" y="-42.67" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B2"/>
<wire x1="-17.78" y1="-45.72" x2="-22.86" y2="-45.72" width="0.1524" layer="91"/>
<label x="-22.86" y="-45.21" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C1"/>
<wire x1="17.78" y1="38.10" x2="22.86" y2="38.10" width="0.1524" layer="91"/>
<label x="22.86" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C2"/>
<wire x1="17.78" y1="35.56" x2="22.86" y2="35.56" width="0.1524" layer="91"/>
<label x="22.86" y="36.07" size="1.778" layer="95"/></segment>
<segment><pinref part="CD1" gate="G$1" pin="1"/>
<wire x1="122.22" y1="-1219.20" x2="117.14" y2="-1219.20" width="0.1524" layer="91"/>
<label x="117.14" y="-1218.69" size="1.778" layer="95"/></segment>
<segment><pinref part="CD2" gate="G$1" pin="1"/>
<wire x1="223.82" y1="-1219.20" x2="218.74" y2="-1219.20" width="0.1524" layer="91"/>
<label x="218.74" y="-1218.69" size="1.778" layer="95"/></segment>
<segment><pinref part="CD3" gate="G$1" pin="1"/>
<wire x1="325.42" y1="-1219.20" x2="320.34" y2="-1219.20" width="0.1524" layer="91"/>
<label x="320.34" y="-1218.69" size="1.778" layer="95"/></segment>
<segment><pinref part="CD4" gate="G$1" pin="1"/>
<wire x1="427.02" y1="-1219.20" x2="421.94" y2="-1219.20" width="0.1524" layer="91"/>
<label x="421.94" y="-1218.69" size="1.778" layer="95"/></segment>
<segment><pinref part="CD5" gate="G$1" pin="1"/>
<wire x1="122.22" y1="-1358.90" x2="117.14" y2="-1358.90" width="0.1524" layer="91"/>
<label x="117.14" y="-1358.39" size="1.778" layer="95"/></segment>
<segment><pinref part="CD6" gate="G$1" pin="1"/>
<wire x1="223.82" y1="-1358.90" x2="218.74" y2="-1358.90" width="0.1524" layer="91"/>
<label x="218.74" y="-1358.39" size="1.778" layer="95"/></segment>
<segment><pinref part="CD7" gate="G$1" pin="1"/>
<wire x1="325.42" y1="-1358.90" x2="320.34" y2="-1358.90" width="0.1524" layer="91"/>
<label x="320.34" y="-1358.39" size="1.778" layer="95"/></segment>
<segment><pinref part="CD8" gate="G$1" pin="1"/>
<wire x1="427.02" y1="-1358.90" x2="421.94" y2="-1358.90" width="0.1524" layer="91"/>
<label x="421.94" y="-1358.39" size="1.778" layer="95"/></segment>
<segment><pinref part="CD9" gate="G$1" pin="1"/>
<wire x1="122.22" y1="-1498.60" x2="117.14" y2="-1498.60" width="0.1524" layer="91"/>
<label x="117.14" y="-1498.09" size="1.778" layer="95"/></segment>
<segment><pinref part="CD10" gate="G$1" pin="1"/>
<wire x1="223.82" y1="-1498.60" x2="218.74" y2="-1498.60" width="0.1524" layer="91"/>
<label x="218.74" y="-1498.09" size="1.778" layer="95"/></segment>
<segment><pinref part="CD11" gate="G$1" pin="1"/>
<wire x1="325.42" y1="-1498.60" x2="320.34" y2="-1498.60" width="0.1524" layer="91"/>
<label x="320.34" y="-1498.09" size="1.778" layer="95"/></segment>
<segment><pinref part="CD12" gate="G$1" pin="1"/>
<wire x1="427.02" y1="-1498.60" x2="421.94" y2="-1498.60" width="0.1524" layer="91"/>
<label x="421.94" y="-1498.09" size="1.778" layer="95"/></segment>
<segment><pinref part="CD13" gate="G$1" pin="1"/>
<wire x1="122.22" y1="-1638.30" x2="117.14" y2="-1638.30" width="0.1524" layer="91"/>
<label x="117.14" y="-1637.79" size="1.778" layer="95"/></segment>
<segment><pinref part="CD14" gate="G$1" pin="1"/>
<wire x1="223.82" y1="-1638.30" x2="218.74" y2="-1638.30" width="0.1524" layer="91"/>
<label x="218.74" y="-1637.79" size="1.778" layer="95"/></segment>
<segment><pinref part="CD15" gate="G$1" pin="1"/>
<wire x1="325.42" y1="-1638.30" x2="320.34" y2="-1638.30" width="0.1524" layer="91"/>
<label x="320.34" y="-1637.79" size="1.778" layer="95"/></segment>
<segment><pinref part="CD16" gate="G$1" pin="1"/>
<wire x1="427.02" y1="-1638.30" x2="421.94" y2="-1638.30" width="0.1524" layer="91"/>
<label x="421.94" y="-1637.79" size="1.778" layer="95"/></segment>
<segment><pinref part="CD17" gate="G$1" pin="1"/>
<wire x1="122.22" y1="-1778.00" x2="117.14" y2="-1778.00" width="0.1524" layer="91"/>
<label x="117.14" y="-1777.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD18" gate="G$1" pin="1"/>
<wire x1="223.82" y1="-1778.00" x2="218.74" y2="-1778.00" width="0.1524" layer="91"/>
<label x="218.74" y="-1777.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD19" gate="G$1" pin="1"/>
<wire x1="325.42" y1="-1778.00" x2="320.34" y2="-1778.00" width="0.1524" layer="91"/>
<label x="320.34" y="-1777.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD20" gate="G$1" pin="1"/>
<wire x1="427.02" y1="-1778.00" x2="421.94" y2="-1778.00" width="0.1524" layer="91"/>
<label x="421.94" y="-1777.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD21" gate="G$1" pin="1"/>
<wire x1="122.22" y1="-1917.70" x2="117.14" y2="-1917.70" width="0.1524" layer="91"/>
<label x="117.14" y="-1917.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U1" gate="G$1" pin="VCC"/>
<wire x1="157.78" y1="25.40" x2="162.86" y2="25.40" width="0.1524" layer="91"/>
<label x="162.86" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="U2" gate="G$1" pin="VCC"/>
<wire x1="259.38" y1="22.86" x2="264.46" y2="22.86" width="0.1524" layer="91"/>
<label x="264.46" y="23.37" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="VCC"/>
<wire x1="360.98" y1="27.94" x2="366.06" y2="27.94" width="0.1524" layer="91"/>
<label x="366.06" y="28.45" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="VCC"/>
<wire x1="462.58" y1="27.94" x2="467.66" y2="27.94" width="0.1524" layer="91"/>
<label x="467.66" y="28.45" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="VCC"/>
<wire x1="157.78" y1="-111.76" x2="162.86" y2="-111.76" width="0.1524" layer="91"/>
<label x="162.86" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="VCC"/>
<wire x1="259.38" y1="-111.76" x2="264.46" y2="-111.76" width="0.1524" layer="91"/>
<label x="264.46" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="U7" gate="G$1" pin="VCC"/>
<wire x1="360.98" y1="-121.92" x2="366.06" y2="-121.92" width="0.1524" layer="91"/>
<label x="366.06" y="-121.41" size="1.778" layer="95"/></segment>
<segment><pinref part="U8" gate="G$1" pin="VCC"/>
<wire x1="462.58" y1="-121.92" x2="467.66" y2="-121.92" width="0.1524" layer="91"/>
<label x="467.66" y="-121.41" size="1.778" layer="95"/></segment>
<segment><pinref part="U9" gate="G$1" pin="VCC"/>
<wire x1="157.78" y1="-246.38" x2="162.86" y2="-246.38" width="0.1524" layer="91"/>
<label x="162.86" y="-245.87" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="VCC"/>
<wire x1="259.38" y1="-274.32" x2="264.46" y2="-274.32" width="0.1524" layer="91"/>
<label x="264.46" y="-273.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="VCC"/>
<wire x1="360.98" y1="-274.32" x2="366.06" y2="-274.32" width="0.1524" layer="91"/>
<label x="366.06" y="-273.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="VCC"/>
<wire x1="462.58" y1="-274.32" x2="467.66" y2="-274.32" width="0.1524" layer="91"/>
<label x="467.66" y="-273.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="VCC"/>
<wire x1="157.78" y1="-414.02" x2="162.86" y2="-414.02" width="0.1524" layer="91"/>
<label x="162.86" y="-413.51" size="1.778" layer="95"/></segment>
<segment><pinref part="U14" gate="G$1" pin="VCC"/>
<wire x1="259.38" y1="-401.32" x2="264.46" y2="-401.32" width="0.1524" layer="91"/>
<label x="264.46" y="-400.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U15" gate="G$1" pin="VCC"/>
<wire x1="360.98" y1="-401.32" x2="366.06" y2="-401.32" width="0.1524" layer="91"/>
<label x="366.06" y="-400.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U16" gate="G$1" pin="VCC"/>
<wire x1="462.58" y1="-401.32" x2="467.66" y2="-401.32" width="0.1524" layer="91"/>
<label x="467.66" y="-400.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U17" gate="G$1" pin="VCC"/>
<wire x1="157.78" y1="-541.02" x2="162.86" y2="-541.02" width="0.1524" layer="91"/>
<label x="162.86" y="-540.51" size="1.778" layer="95"/></segment>
<segment><pinref part="U18" gate="G$1" pin="VCC"/>
<wire x1="259.38" y1="-533.40" x2="264.46" y2="-533.40" width="0.1524" layer="91"/>
<label x="264.46" y="-532.89" size="1.778" layer="95"/></segment>
<segment><pinref part="U19" gate="G$1" pin="VCC"/>
<wire x1="360.98" y1="-530.86" x2="366.06" y2="-530.86" width="0.1524" layer="91"/>
<label x="366.06" y="-530.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="VCC"/>
<wire x1="462.58" y1="-541.02" x2="467.66" y2="-541.02" width="0.1524" layer="91"/>
<label x="467.66" y="-540.51" size="1.778" layer="95"/></segment>
<segment><pinref part="U21" gate="G$1" pin="VCC"/>
<wire x1="157.78" y1="-670.56" x2="162.86" y2="-670.56" width="0.1524" layer="91"/>
<label x="162.86" y="-670.05" size="1.778" layer="95"/></segment>
</net>
<net name="GND" class="0">
<segment><pinref part="U1" gate="G$1" pin="A"/>
<wire x1="122.22" y1="33.02" x2="117.14" y2="33.02" width="0.1524" layer="91"/>
<label x="117.14" y="33.53" size="1.778" layer="95"/></segment>
<segment><pinref part="U1" gate="G$1" pin="B"/>
<wire x1="122.22" y1="30.48" x2="117.14" y2="30.48" width="0.1524" layer="91"/>
<label x="117.14" y="30.99" size="1.778" layer="95"/></segment>
<segment><pinref part="U1" gate="G$1" pin="C"/>
<wire x1="122.22" y1="27.94" x2="117.14" y2="27.94" width="0.1524" layer="91"/>
<label x="117.14" y="28.45" size="1.778" layer="95"/></segment>
<segment><pinref part="U1" gate="G$1" pin="D"/>
<wire x1="122.22" y1="25.40" x2="117.14" y2="25.40" width="0.1524" layer="91"/>
<label x="117.14" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="U18" gate="G$1" pin="A"/>
<wire x1="223.82" y1="-525.78" x2="218.74" y2="-525.78" width="0.1524" layer="91"/>
<label x="218.74" y="-525.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U18" gate="G$1" pin="B"/>
<wire x1="223.82" y1="-528.32" x2="218.74" y2="-528.32" width="0.1524" layer="91"/>
<label x="218.74" y="-527.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U18" gate="G$1" pin="C"/>
<wire x1="223.82" y1="-530.86" x2="218.74" y2="-530.86" width="0.1524" layer="91"/>
<label x="218.74" y="-530.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U18" gate="G$1" pin="D"/>
<wire x1="223.82" y1="-533.40" x2="218.74" y2="-533.40" width="0.1524" layer="91"/>
<label x="218.74" y="-532.89" size="1.778" layer="95"/></segment>
<segment><pinref part="U9" gate="G$1" pin="D0"/>
<wire x1="122.22" y1="-248.92" x2="117.14" y2="-248.92" width="0.1524" layer="91"/>
<label x="117.14" y="-248.41" size="1.778" layer="95"/></segment>
<segment><pinref part="U9" gate="G$1" pin="!G"/>
<wire x1="122.22" y1="-269.24" x2="117.14" y2="-269.24" width="0.1524" layer="91"/>
<label x="117.14" y="-268.73" size="1.778" layer="95"/></segment>
<segment><pinref part="U8" gate="G$1" pin="!G2B"/>
<wire x1="427.02" y1="-114.30" x2="421.94" y2="-114.30" width="0.1524" layer="91"/>
<label x="421.94" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="X1" gate="G$1" pin="GND"/>
<wire x1="259.38" y1="-665.48" x2="264.46" y2="-665.48" width="0.1524" layer="91"/>
<label x="264.46" y="-664.97" size="1.778" layer="95"/></segment>
<segment><pinref part="SWR" gate="G$1" pin="1"/>
<wire x1="427.02" y1="-660.40" x2="421.94" y2="-660.40" width="0.1524" layer="91"/>
<label x="421.94" y="-659.89" size="1.778" layer="95"/></segment>
<segment><pinref part="SWS" gate="G$1" pin="1"/>
<wire x1="122.22" y1="-800.10" x2="117.14" y2="-800.10" width="0.1524" layer="91"/>
<label x="117.14" y="-799.59" size="1.778" layer="95"/></segment>
<segment><pinref part="SWT" gate="G$1" pin="1"/>
<wire x1="223.82" y1="-800.10" x2="218.74" y2="-800.10" width="0.1524" layer="91"/>
<label x="218.74" y="-799.59" size="1.778" layer="95"/></segment>
<segment><pinref part="C1" gate="G$1" pin="2"/>
<wire x1="259.38" y1="-939.80" x2="264.46" y2="-939.80" width="0.1524" layer="91"/>
<label x="264.46" y="-939.29" size="1.778" layer="95"/></segment>
<segment><pinref part="LED3" gate="G$1" pin="K"/>
<wire x1="462.58" y1="-939.80" x2="467.66" y2="-939.80" width="0.1524" layer="91"/>
<label x="467.66" y="-939.29" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="3A"/>
<wire x1="122.22" y1="-111.76" x2="117.14" y2="-111.76" width="0.1524" layer="91"/>
<label x="117.14" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="3B"/>
<wire x1="122.22" y1="-114.30" x2="117.14" y2="-114.30" width="0.1524" layer="91"/>
<label x="117.14" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="4A"/>
<wire x1="122.22" y1="-116.84" x2="117.14" y2="-116.84" width="0.1524" layer="91"/>
<label x="117.14" y="-116.33" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="4B"/>
<wire x1="122.22" y1="-119.38" x2="117.14" y2="-119.38" width="0.1524" layer="91"/>
<label x="117.14" y="-118.87" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="2A"/>
<wire x1="223.82" y1="-106.68" x2="218.74" y2="-106.68" width="0.1524" layer="91"/>
<label x="218.74" y="-106.17" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="2B"/>
<wire x1="223.82" y1="-109.22" x2="218.74" y2="-109.22" width="0.1524" layer="91"/>
<label x="218.74" y="-108.71" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="3A"/>
<wire x1="223.82" y1="-111.76" x2="218.74" y2="-111.76" width="0.1524" layer="91"/>
<label x="218.74" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="3B"/>
<wire x1="223.82" y1="-114.30" x2="218.74" y2="-114.30" width="0.1524" layer="91"/>
<label x="218.74" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="!CE"/>
<wire x1="259.38" y1="-261.62" x2="264.46" y2="-261.62" width="0.1524" layer="91"/>
<label x="264.46" y="-261.11" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="!CE"/>
<wire x1="360.98" y1="-261.62" x2="366.06" y2="-261.62" width="0.1524" layer="91"/>
<label x="366.06" y="-261.11" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="!CE"/>
<wire x1="462.58" y1="-261.62" x2="467.66" y2="-261.62" width="0.1524" layer="91"/>
<label x="467.66" y="-261.11" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="!CE"/>
<wire x1="157.78" y1="-401.32" x2="162.86" y2="-401.32" width="0.1524" layer="91"/>
<label x="162.86" y="-400.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="!OE"/>
<wire x1="259.38" y1="-264.16" x2="264.46" y2="-264.16" width="0.1524" layer="91"/>
<label x="264.46" y="-263.65" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="!OE"/>
<wire x1="360.98" y1="-264.16" x2="366.06" y2="-264.16" width="0.1524" layer="91"/>
<label x="366.06" y="-263.65" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="!OE"/>
<wire x1="462.58" y1="-264.16" x2="467.66" y2="-264.16" width="0.1524" layer="91"/>
<label x="467.66" y="-263.65" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="!OE"/>
<wire x1="157.78" y1="-403.86" x2="162.86" y2="-403.86" width="0.1524" layer="91"/>
<label x="162.86" y="-403.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U14" gate="G$1" pin="!OC"/>
<wire x1="223.82" y1="-381.00" x2="218.74" y2="-381.00" width="0.1524" layer="91"/>
<label x="218.74" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="U15" gate="G$1" pin="!OC"/>
<wire x1="325.42" y1="-381.00" x2="320.34" y2="-381.00" width="0.1524" layer="91"/>
<label x="320.34" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="U16" gate="G$1" pin="!OC"/>
<wire x1="427.02" y1="-381.00" x2="421.94" y2="-381.00" width="0.1524" layer="91"/>
<label x="421.94" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="U17" gate="G$1" pin="!OC"/>
<wire x1="122.22" y1="-520.70" x2="117.14" y2="-520.70" width="0.1524" layer="91"/>
<label x="117.14" y="-520.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U19" gate="G$1" pin="2A"/>
<wire x1="325.42" y1="-525.78" x2="320.34" y2="-525.78" width="0.1524" layer="91"/>
<label x="320.34" y="-525.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U19" gate="G$1" pin="2B"/>
<wire x1="325.42" y1="-528.32" x2="320.34" y2="-528.32" width="0.1524" layer="91"/>
<label x="320.34" y="-527.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U19" gate="G$1" pin="3A"/>
<wire x1="325.42" y1="-530.86" x2="320.34" y2="-530.86" width="0.1524" layer="91"/>
<label x="320.34" y="-530.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U19" gate="G$1" pin="3B"/>
<wire x1="325.42" y1="-533.40" x2="320.34" y2="-533.40" width="0.1524" layer="91"/>
<label x="320.34" y="-532.89" size="1.778" layer="95"/></segment>
<segment><pinref part="U19" gate="G$1" pin="4A"/>
<wire x1="325.42" y1="-535.94" x2="320.34" y2="-535.94" width="0.1524" layer="91"/>
<label x="320.34" y="-535.43" size="1.778" layer="95"/></segment>
<segment><pinref part="U19" gate="G$1" pin="4B"/>
<wire x1="325.42" y1="-538.48" x2="320.34" y2="-538.48" width="0.1524" layer="91"/>
<label x="320.34" y="-537.97" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="A1"/>
<wire x1="427.02" y1="-523.24" x2="421.94" y2="-523.24" width="0.1524" layer="91"/>
<label x="421.94" y="-522.73" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="A2"/>
<wire x1="427.02" y1="-525.78" x2="421.94" y2="-525.78" width="0.1524" layer="91"/>
<label x="421.94" y="-525.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="A3"/>
<wire x1="427.02" y1="-528.32" x2="421.94" y2="-528.32" width="0.1524" layer="91"/>
<label x="421.94" y="-527.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="A5"/>
<wire x1="427.02" y1="-535.94" x2="421.94" y2="-535.94" width="0.1524" layer="91"/>
<label x="421.94" y="-535.43" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="A6"/>
<wire x1="427.02" y1="-538.48" x2="421.94" y2="-538.48" width="0.1524" layer="91"/>
<label x="421.94" y="-537.97" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="A7"/>
<wire x1="427.02" y1="-541.02" x2="421.94" y2="-541.02" width="0.1524" layer="91"/>
<label x="421.94" y="-540.51" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="A8"/>
<wire x1="427.02" y1="-543.56" x2="421.94" y2="-543.56" width="0.1524" layer="91"/>
<label x="421.94" y="-543.05" size="1.778" layer="95"/></segment>
<segment><pinref part="U21" gate="G$1" pin="1CLK"/>
<wire x1="122.22" y1="-665.48" x2="117.14" y2="-665.48" width="0.1524" layer="91"/>
<label x="117.14" y="-664.97" size="1.778" layer="95"/></segment>
<segment><pinref part="U21" gate="G$1" pin="2D"/>
<wire x1="122.22" y1="-673.10" x2="117.14" y2="-673.10" width="0.1524" layer="91"/>
<label x="117.14" y="-672.59" size="1.778" layer="95"/></segment>
<segment><pinref part="U21" gate="G$1" pin="2CLK"/>
<wire x1="122.22" y1="-675.64" x2="117.14" y2="-675.64" width="0.1524" layer="91"/>
<label x="117.14" y="-675.13" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A31"/>
<wire x1="-17.78" y1="-38.10" x2="-22.86" y2="-38.10" width="0.1524" layer="91"/>
<label x="-22.86" y="-37.59" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A32"/>
<wire x1="-17.78" y1="-40.64" x2="-22.86" y2="-40.64" width="0.1524" layer="91"/>
<label x="-22.86" y="-40.13" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B3"/>
<wire x1="-17.78" y1="-48.26" x2="-22.86" y2="-48.26" width="0.1524" layer="91"/>
<label x="-22.86" y="-47.75" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B5"/>
<wire x1="-17.78" y1="-53.34" x2="-22.86" y2="-53.34" width="0.1524" layer="91"/>
<label x="-22.86" y="-52.83" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B7"/>
<wire x1="-17.78" y1="-58.42" x2="-22.86" y2="-58.42" width="0.1524" layer="91"/>
<label x="-22.86" y="-57.91" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B9"/>
<wire x1="-17.78" y1="-63.50" x2="-22.86" y2="-63.50" width="0.1524" layer="91"/>
<label x="-22.86" y="-62.99" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B11"/>
<wire x1="-17.78" y1="-68.58" x2="-22.86" y2="-68.58" width="0.1524" layer="91"/>
<label x="-22.86" y="-68.07" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B13"/>
<wire x1="-17.78" y1="-73.66" x2="-22.86" y2="-73.66" width="0.1524" layer="91"/>
<label x="-22.86" y="-73.15" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B15"/>
<wire x1="-17.78" y1="-78.74" x2="-22.86" y2="-78.74" width="0.1524" layer="91"/>
<label x="-22.86" y="-78.23" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B17"/>
<wire x1="-17.78" y1="-83.82" x2="-22.86" y2="-83.82" width="0.1524" layer="91"/>
<label x="-22.86" y="-83.31" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B19"/>
<wire x1="-17.78" y1="-88.90" x2="-22.86" y2="-88.90" width="0.1524" layer="91"/>
<label x="-22.86" y="-88.39" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B21"/>
<wire x1="-17.78" y1="-93.98" x2="-22.86" y2="-93.98" width="0.1524" layer="91"/>
<label x="-22.86" y="-93.47" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B23"/>
<wire x1="-17.78" y1="-99.06" x2="-22.86" y2="-99.06" width="0.1524" layer="91"/>
<label x="-22.86" y="-98.55" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B25"/>
<wire x1="-17.78" y1="-104.14" x2="-22.86" y2="-104.14" width="0.1524" layer="91"/>
<label x="-22.86" y="-103.63" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B31"/>
<wire x1="-17.78" y1="-119.38" x2="-22.86" y2="-119.38" width="0.1524" layer="91"/>
<label x="-22.86" y="-118.87" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B32"/>
<wire x1="-17.78" y1="-121.92" x2="-22.86" y2="-121.92" width="0.1524" layer="91"/>
<label x="-22.86" y="-121.41" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C31"/>
<wire x1="17.78" y1="-38.10" x2="22.86" y2="-38.10" width="0.1524" layer="91"/>
<label x="22.86" y="-37.59" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C32"/>
<wire x1="17.78" y1="-40.64" x2="22.86" y2="-40.64" width="0.1524" layer="91"/>
<label x="22.86" y="-40.13" size="1.778" layer="95"/></segment>
<segment><pinref part="CD1" gate="G$1" pin="2"/>
<wire x1="157.78" y1="-1219.20" x2="162.86" y2="-1219.20" width="0.1524" layer="91"/>
<label x="162.86" y="-1218.69" size="1.778" layer="95"/></segment>
<segment><pinref part="CD2" gate="G$1" pin="2"/>
<wire x1="259.38" y1="-1219.20" x2="264.46" y2="-1219.20" width="0.1524" layer="91"/>
<label x="264.46" y="-1218.69" size="1.778" layer="95"/></segment>
<segment><pinref part="CD3" gate="G$1" pin="2"/>
<wire x1="360.98" y1="-1219.20" x2="366.06" y2="-1219.20" width="0.1524" layer="91"/>
<label x="366.06" y="-1218.69" size="1.778" layer="95"/></segment>
<segment><pinref part="CD4" gate="G$1" pin="2"/>
<wire x1="462.58" y1="-1219.20" x2="467.66" y2="-1219.20" width="0.1524" layer="91"/>
<label x="467.66" y="-1218.69" size="1.778" layer="95"/></segment>
<segment><pinref part="CD5" gate="G$1" pin="2"/>
<wire x1="157.78" y1="-1358.90" x2="162.86" y2="-1358.90" width="0.1524" layer="91"/>
<label x="162.86" y="-1358.39" size="1.778" layer="95"/></segment>
<segment><pinref part="CD6" gate="G$1" pin="2"/>
<wire x1="259.38" y1="-1358.90" x2="264.46" y2="-1358.90" width="0.1524" layer="91"/>
<label x="264.46" y="-1358.39" size="1.778" layer="95"/></segment>
<segment><pinref part="CD7" gate="G$1" pin="2"/>
<wire x1="360.98" y1="-1358.90" x2="366.06" y2="-1358.90" width="0.1524" layer="91"/>
<label x="366.06" y="-1358.39" size="1.778" layer="95"/></segment>
<segment><pinref part="CD8" gate="G$1" pin="2"/>
<wire x1="462.58" y1="-1358.90" x2="467.66" y2="-1358.90" width="0.1524" layer="91"/>
<label x="467.66" y="-1358.39" size="1.778" layer="95"/></segment>
<segment><pinref part="CD9" gate="G$1" pin="2"/>
<wire x1="157.78" y1="-1498.60" x2="162.86" y2="-1498.60" width="0.1524" layer="91"/>
<label x="162.86" y="-1498.09" size="1.778" layer="95"/></segment>
<segment><pinref part="CD10" gate="G$1" pin="2"/>
<wire x1="259.38" y1="-1498.60" x2="264.46" y2="-1498.60" width="0.1524" layer="91"/>
<label x="264.46" y="-1498.09" size="1.778" layer="95"/></segment>
<segment><pinref part="CD11" gate="G$1" pin="2"/>
<wire x1="360.98" y1="-1498.60" x2="366.06" y2="-1498.60" width="0.1524" layer="91"/>
<label x="366.06" y="-1498.09" size="1.778" layer="95"/></segment>
<segment><pinref part="CD12" gate="G$1" pin="2"/>
<wire x1="462.58" y1="-1498.60" x2="467.66" y2="-1498.60" width="0.1524" layer="91"/>
<label x="467.66" y="-1498.09" size="1.778" layer="95"/></segment>
<segment><pinref part="CD13" gate="G$1" pin="2"/>
<wire x1="157.78" y1="-1638.30" x2="162.86" y2="-1638.30" width="0.1524" layer="91"/>
<label x="162.86" y="-1637.79" size="1.778" layer="95"/></segment>
<segment><pinref part="CD14" gate="G$1" pin="2"/>
<wire x1="259.38" y1="-1638.30" x2="264.46" y2="-1638.30" width="0.1524" layer="91"/>
<label x="264.46" y="-1637.79" size="1.778" layer="95"/></segment>
<segment><pinref part="CD15" gate="G$1" pin="2"/>
<wire x1="360.98" y1="-1638.30" x2="366.06" y2="-1638.30" width="0.1524" layer="91"/>
<label x="366.06" y="-1637.79" size="1.778" layer="95"/></segment>
<segment><pinref part="CD16" gate="G$1" pin="2"/>
<wire x1="462.58" y1="-1638.30" x2="467.66" y2="-1638.30" width="0.1524" layer="91"/>
<label x="467.66" y="-1637.79" size="1.778" layer="95"/></segment>
<segment><pinref part="CD17" gate="G$1" pin="2"/>
<wire x1="157.78" y1="-1778.00" x2="162.86" y2="-1778.00" width="0.1524" layer="91"/>
<label x="162.86" y="-1777.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD18" gate="G$1" pin="2"/>
<wire x1="259.38" y1="-1778.00" x2="264.46" y2="-1778.00" width="0.1524" layer="91"/>
<label x="264.46" y="-1777.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD19" gate="G$1" pin="2"/>
<wire x1="360.98" y1="-1778.00" x2="366.06" y2="-1778.00" width="0.1524" layer="91"/>
<label x="366.06" y="-1777.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD20" gate="G$1" pin="2"/>
<wire x1="462.58" y1="-1778.00" x2="467.66" y2="-1778.00" width="0.1524" layer="91"/>
<label x="467.66" y="-1777.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD21" gate="G$1" pin="2"/>
<wire x1="157.78" y1="-1917.70" x2="162.86" y2="-1917.70" width="0.1524" layer="91"/>
<label x="162.86" y="-1917.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U1" gate="G$1" pin="GND"/>
<wire x1="157.78" y1="22.86" x2="162.86" y2="22.86" width="0.1524" layer="91"/>
<label x="162.86" y="23.37" size="1.778" layer="95"/></segment>
<segment><pinref part="U2" gate="G$1" pin="GND"/>
<wire x1="259.38" y1="20.32" x2="264.46" y2="20.32" width="0.1524" layer="91"/>
<label x="264.46" y="20.83" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="GND"/>
<wire x1="360.98" y1="25.40" x2="366.06" y2="25.40" width="0.1524" layer="91"/>
<label x="366.06" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="GND"/>
<wire x1="462.58" y1="25.40" x2="467.66" y2="25.40" width="0.1524" layer="91"/>
<label x="467.66" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="GND"/>
<wire x1="157.78" y1="-114.30" x2="162.86" y2="-114.30" width="0.1524" layer="91"/>
<label x="162.86" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="GND"/>
<wire x1="259.38" y1="-114.30" x2="264.46" y2="-114.30" width="0.1524" layer="91"/>
<label x="264.46" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="U7" gate="G$1" pin="GND"/>
<wire x1="360.98" y1="-124.46" x2="366.06" y2="-124.46" width="0.1524" layer="91"/>
<label x="366.06" y="-123.95" size="1.778" layer="95"/></segment>
<segment><pinref part="U8" gate="G$1" pin="GND"/>
<wire x1="462.58" y1="-124.46" x2="467.66" y2="-124.46" width="0.1524" layer="91"/>
<label x="467.66" y="-123.95" size="1.778" layer="95"/></segment>
<segment><pinref part="U9" gate="G$1" pin="GND"/>
<wire x1="157.78" y1="-248.92" x2="162.86" y2="-248.92" width="0.1524" layer="91"/>
<label x="162.86" y="-248.41" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="GND"/>
<wire x1="259.38" y1="-276.86" x2="264.46" y2="-276.86" width="0.1524" layer="91"/>
<label x="264.46" y="-276.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="GND"/>
<wire x1="360.98" y1="-276.86" x2="366.06" y2="-276.86" width="0.1524" layer="91"/>
<label x="366.06" y="-276.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="GND"/>
<wire x1="462.58" y1="-276.86" x2="467.66" y2="-276.86" width="0.1524" layer="91"/>
<label x="467.66" y="-276.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="GND"/>
<wire x1="157.78" y1="-416.56" x2="162.86" y2="-416.56" width="0.1524" layer="91"/>
<label x="162.86" y="-416.05" size="1.778" layer="95"/></segment>
<segment><pinref part="U14" gate="G$1" pin="GND"/>
<wire x1="259.38" y1="-403.86" x2="264.46" y2="-403.86" width="0.1524" layer="91"/>
<label x="264.46" y="-403.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U15" gate="G$1" pin="GND"/>
<wire x1="360.98" y1="-403.86" x2="366.06" y2="-403.86" width="0.1524" layer="91"/>
<label x="366.06" y="-403.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U16" gate="G$1" pin="GND"/>
<wire x1="462.58" y1="-403.86" x2="467.66" y2="-403.86" width="0.1524" layer="91"/>
<label x="467.66" y="-403.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U17" gate="G$1" pin="GND"/>
<wire x1="157.78" y1="-543.56" x2="162.86" y2="-543.56" width="0.1524" layer="91"/>
<label x="162.86" y="-543.05" size="1.778" layer="95"/></segment>
<segment><pinref part="U18" gate="G$1" pin="GND"/>
<wire x1="259.38" y1="-535.94" x2="264.46" y2="-535.94" width="0.1524" layer="91"/>
<label x="264.46" y="-535.43" size="1.778" layer="95"/></segment>
<segment><pinref part="U19" gate="G$1" pin="GND"/>
<wire x1="360.98" y1="-533.40" x2="366.06" y2="-533.40" width="0.1524" layer="91"/>
<label x="366.06" y="-532.89" size="1.778" layer="95"/></segment>
<segment><pinref part="U20" gate="G$1" pin="GND"/>
<wire x1="462.58" y1="-543.56" x2="467.66" y2="-543.56" width="0.1524" layer="91"/>
<label x="467.66" y="-543.05" size="1.778" layer="95"/></segment>
<segment><pinref part="U21" gate="G$1" pin="GND"/>
<wire x1="157.78" y1="-673.10" x2="162.86" y2="-673.10" width="0.1524" layer="91"/>
<label x="162.86" y="-672.59" size="1.778" layer="95"/></segment>
</net>
<net name="RUNSW" class="0">
<segment><pinref part="SWR" gate="G$1" pin="2"/>
<wire x1="462.58" y1="-660.40" x2="467.66" y2="-660.40" width="0.1524" layer="91"/>
<label x="467.66" y="-659.89" size="1.778" layer="95"/></segment>
<segment><pinref part="R3" gate="G$1" pin="2"/>
<wire x1="157.78" y1="-939.80" x2="162.86" y2="-939.80" width="0.1524" layer="91"/>
<label x="162.86" y="-939.29" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="2A"/>
<wire x1="122.22" y1="-106.68" x2="117.14" y2="-106.68" width="0.1524" layer="91"/>
<label x="117.14" y="-106.17" size="1.778" layer="95"/></segment>
</net>
<net name="HALT" class="0">
<segment><pinref part="U2" gate="G$1" pin="1A"/>
<wire x1="223.82" y1="38.10" x2="218.74" y2="38.10" width="0.1524" layer="91"/>
<label x="218.74" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="U17" gate="G$1" pin="Q3"/>
<wire x1="157.78" y1="-525.78" x2="162.86" y2="-525.78" width="0.1524" layer="91"/>
<label x="162.86" y="-525.27" size="1.778" layer="95"/></segment>
</net>
<net name="HALTN" class="0">
<segment><pinref part="U2" gate="G$1" pin="1Y"/>
<wire x1="259.38" y1="38.10" x2="264.46" y2="38.10" width="0.1524" layer="91"/>
<label x="264.46" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="2B"/>
<wire x1="122.22" y1="-109.22" x2="117.14" y2="-109.22" width="0.1524" layer="91"/>
<label x="117.14" y="-108.71" size="1.778" layer="95"/></segment>
</net>
<net name="RUND" class="0">
<segment><pinref part="U5" gate="G$1" pin="2Y"/>
<wire x1="157.78" y1="-104.14" x2="162.86" y2="-104.14" width="0.1524" layer="91"/>
<label x="162.86" y="-103.63" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="1D"/>
<wire x1="325.42" y1="35.56" x2="320.34" y2="35.56" width="0.1524" layer="91"/>
<label x="320.34" y="36.07" size="1.778" layer="95"/></segment>
</net>
<net name="STEPRAW" class="0">
<segment><pinref part="SWS" gate="G$1" pin="2"/>
<wire x1="157.78" y1="-800.10" x2="162.86" y2="-800.10" width="0.1524" layer="91"/>
<label x="162.86" y="-799.59" size="1.778" layer="95"/></segment>
<segment><pinref part="R2" gate="G$1" pin="2"/>
<wire x1="462.58" y1="-800.10" x2="467.66" y2="-800.10" width="0.1524" layer="91"/>
<label x="467.66" y="-799.59" size="1.778" layer="95"/></segment>
<segment><pinref part="U2" gate="G$1" pin="2A"/>
<wire x1="223.82" y1="35.56" x2="218.74" y2="35.56" width="0.1524" layer="91"/>
<label x="218.74" y="36.07" size="1.778" layer="95"/></segment>
</net>
<net name="STEPN" class="0">
<segment><pinref part="U2" gate="G$1" pin="2Y"/>
<wire x1="259.38" y1="35.56" x2="264.46" y2="35.56" width="0.1524" layer="91"/>
<label x="264.46" y="36.07" size="1.778" layer="95"/></segment>
<segment><pinref part="U2" gate="G$1" pin="3A"/>
<wire x1="223.82" y1="33.02" x2="218.74" y2="33.02" width="0.1524" layer="91"/>
<label x="218.74" y="33.53" size="1.778" layer="95"/></segment>
</net>
<net name="STEPP" class="0">
<segment><pinref part="U2" gate="G$1" pin="3Y"/>
<wire x1="259.38" y1="33.02" x2="264.46" y2="33.02" width="0.1524" layer="91"/>
<label x="264.46" y="33.53" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="2D"/>
<wire x1="325.42" y1="25.40" x2="320.34" y2="25.40" width="0.1524" layer="91"/>
<label x="320.34" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="1B"/>
<wire x1="427.02" y1="35.56" x2="421.94" y2="35.56" width="0.1524" layer="91"/>
<label x="421.94" y="36.07" size="1.778" layer="95"/></segment>
</net>
<net name="STEPQ" class="0">
<segment><pinref part="U3" gate="G$1" pin="2Q"/>
<wire x1="360.98" y1="33.02" x2="366.06" y2="33.02" width="0.1524" layer="91"/>
<label x="366.06" y="33.53" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="1A"/>
<wire x1="427.02" y1="38.10" x2="421.94" y2="38.10" width="0.1524" layer="91"/>
<label x="421.94" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="1B"/>
<wire x1="223.82" y1="-104.14" x2="218.74" y2="-104.14" width="0.1524" layer="91"/>
<label x="218.74" y="-103.63" size="1.778" layer="95"/></segment>
</net>
<net name="STEPCLR" class="0">
<segment><pinref part="U4" gate="G$1" pin="1Y"/>
<wire x1="462.58" y1="38.10" x2="467.66" y2="38.10" width="0.1524" layer="91"/>
<label x="467.66" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="!2CLR"/>
<wire x1="325.42" y1="27.94" x2="320.34" y2="27.94" width="0.1524" layer="91"/>
<label x="320.34" y="28.45" size="1.778" layer="95"/></segment>
</net>
<net name="RUNQ" class="0">
<segment><pinref part="U3" gate="G$1" pin="1Q"/>
<wire x1="360.98" y1="38.10" x2="366.06" y2="38.10" width="0.1524" layer="91"/>
<label x="366.06" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="1A"/>
<wire x1="223.82" y1="-101.60" x2="218.74" y2="-101.60" width="0.1524" layer="91"/>
<label x="218.74" y="-101.09" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="3A"/>
<wire x1="427.02" y1="27.94" x2="421.94" y2="27.94" width="0.1524" layer="91"/>
<label x="421.94" y="28.45" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="3B"/>
<wire x1="427.02" y1="25.40" x2="421.94" y2="25.40" width="0.1524" layer="91"/>
<label x="421.94" y="25.91" size="1.778" layer="95"/></segment>
</net>
<net name="RUNLK" class="0">
<segment><pinref part="U4" gate="G$1" pin="3Y"/>
<wire x1="462.58" y1="33.02" x2="467.66" y2="33.02" width="0.1524" layer="91"/>
<label x="467.66" y="33.53" size="1.778" layer="95"/></segment>
<segment><pinref part="LED4" gate="G$1" pin="K"/>
<wire x1="259.38" y1="-1079.50" x2="264.46" y2="-1079.50" width="0.1524" layer="91"/>
<label x="264.46" y="-1078.99" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="4A"/>
<wire x1="427.02" y1="22.86" x2="421.94" y2="22.86" width="0.1524" layer="91"/>
<label x="421.94" y="23.37" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="4B"/>
<wire x1="427.02" y1="20.32" x2="421.94" y2="20.32" width="0.1524" layer="91"/>
<label x="421.94" y="20.83" size="1.778" layer="95"/></segment>
</net>
<net name="HALTK" class="0">
<segment><pinref part="U4" gate="G$1" pin="4Y"/>
<wire x1="462.58" y1="30.48" x2="467.66" y2="30.48" width="0.1524" layer="91"/>
<label x="467.66" y="30.99" size="1.778" layer="95"/></segment>
<segment><pinref part="LED5" gate="G$1" pin="K"/>
<wire x1="462.58" y1="-1079.50" x2="467.66" y2="-1079.50" width="0.1524" layer="91"/>
<label x="467.66" y="-1078.99" size="1.778" layer="95"/></segment>
</net>
<net name="CLKEN" class="0">
<segment><pinref part="U6" gate="G$1" pin="1Y"/>
<wire x1="259.38" y1="-101.60" x2="264.46" y2="-101.60" width="0.1524" layer="91"/>
<label x="264.46" y="-101.09" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="1B"/>
<wire x1="122.22" y1="-104.14" x2="117.14" y2="-104.14" width="0.1524" layer="91"/>
<label x="117.14" y="-103.63" size="1.778" layer="95"/></segment>
</net>
<net name="CLK" class="0">
<segment><pinref part="U5" gate="G$1" pin="1Y"/>
<wire x1="157.78" y1="-101.60" x2="162.86" y2="-101.60" width="0.1524" layer="91"/>
<label x="162.86" y="-101.09" size="1.778" layer="95"/></segment>
<segment><pinref part="U2" gate="G$1" pin="6A"/>
<wire x1="223.82" y1="25.40" x2="218.74" y2="25.40" width="0.1524" layer="91"/>
<label x="218.74" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="U7" gate="G$1" pin="CLK"/>
<wire x1="325.42" y1="-104.14" x2="320.34" y2="-104.14" width="0.1524" layer="91"/>
<label x="320.34" y="-103.63" size="1.778" layer="95"/></segment>
<segment><pinref part="U18" gate="G$1" pin="CLK"/>
<wire x1="223.82" y1="-523.24" x2="218.74" y2="-523.24" width="0.1524" layer="91"/>
<label x="218.74" y="-522.73" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A24"/>
<wire x1="-17.78" y1="-20.32" x2="-22.86" y2="-20.32" width="0.1524" layer="91"/>
<label x="-22.86" y="-19.81" size="1.778" layer="95"/></segment>
</net>
<net name="CLKB" class="0">
<segment><pinref part="U2" gate="G$1" pin="6Y"/>
<wire x1="259.38" y1="25.40" x2="264.46" y2="25.40" width="0.1524" layer="91"/>
<label x="264.46" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="U14" gate="G$1" pin="CLK"/>
<wire x1="223.82" y1="-383.54" x2="218.74" y2="-383.54" width="0.1524" layer="91"/>
<label x="218.74" y="-383.03" size="1.778" layer="95"/></segment>
<segment><pinref part="U15" gate="G$1" pin="CLK"/>
<wire x1="325.42" y1="-383.54" x2="320.34" y2="-383.54" width="0.1524" layer="91"/>
<label x="320.34" y="-383.03" size="1.778" layer="95"/></segment>
<segment><pinref part="U16" gate="G$1" pin="CLK"/>
<wire x1="427.02" y1="-383.54" x2="421.94" y2="-383.54" width="0.1524" layer="91"/>
<label x="421.94" y="-383.03" size="1.778" layer="95"/></segment>
<segment><pinref part="U17" gate="G$1" pin="CLK"/>
<wire x1="122.22" y1="-523.24" x2="117.14" y2="-523.24" width="0.1524" layer="91"/>
<label x="117.14" y="-522.73" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A25"/>
<wire x1="-17.78" y1="-22.86" x2="-22.86" y2="-22.86" width="0.1524" layer="91"/>
<label x="-22.86" y="-22.35" size="1.778" layer="95"/></segment>
</net>
<net name="RSTRAW" class="0">
<segment><pinref part="SWT" gate="G$1" pin="2"/>
<wire x1="259.38" y1="-800.10" x2="264.46" y2="-800.10" width="0.1524" layer="91"/>
<label x="264.46" y="-799.59" size="1.778" layer="95"/></segment>
<segment><pinref part="R1" gate="G$1" pin="2"/>
<wire x1="360.98" y1="-800.10" x2="366.06" y2="-800.10" width="0.1524" layer="91"/>
<label x="366.06" y="-799.59" size="1.778" layer="95"/></segment>
<segment><pinref part="C1" gate="G$1" pin="1"/>
<wire x1="223.82" y1="-939.80" x2="218.74" y2="-939.80" width="0.1524" layer="91"/>
<label x="218.74" y="-939.29" size="1.778" layer="95"/></segment>
<segment><pinref part="U2" gate="G$1" pin="4A"/>
<wire x1="223.82" y1="30.48" x2="218.74" y2="30.48" width="0.1524" layer="91"/>
<label x="218.74" y="30.99" size="1.778" layer="95"/></segment>
</net>
<net name="RSTP" class="0">
<segment><pinref part="U2" gate="G$1" pin="4Y"/>
<wire x1="259.38" y1="30.48" x2="264.46" y2="30.48" width="0.1524" layer="91"/>
<label x="264.46" y="30.99" size="1.778" layer="95"/></segment>
<segment><pinref part="U2" gate="G$1" pin="5A"/>
<wire x1="223.82" y1="27.94" x2="218.74" y2="27.94" width="0.1524" layer="91"/>
<label x="218.74" y="28.45" size="1.778" layer="95"/></segment>
</net>
<net name="-RES" class="0">
<segment><pinref part="U2" gate="G$1" pin="5Y"/>
<wire x1="259.38" y1="27.94" x2="264.46" y2="27.94" width="0.1524" layer="91"/>
<label x="264.46" y="28.45" size="1.778" layer="95"/></segment>
<segment><pinref part="U1" gate="G$1" pin="!CLR"/>
<wire x1="122.22" y1="38.10" x2="117.14" y2="38.10" width="0.1524" layer="91"/>
<label x="117.14" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="!1CLR"/>
<wire x1="325.42" y1="38.10" x2="320.34" y2="38.10" width="0.1524" layer="91"/>
<label x="320.34" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="U18" gate="G$1" pin="!CLR"/>
<wire x1="223.82" y1="-520.70" x2="218.74" y2="-520.70" width="0.1524" layer="91"/>
<label x="218.74" y="-520.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U21" gate="G$1" pin="!1CLR"/>
<wire x1="122.22" y1="-660.40" x2="117.14" y2="-660.40" width="0.1524" layer="91"/>
<label x="117.14" y="-659.89" size="1.778" layer="95"/></segment>
<segment><pinref part="U21" gate="G$1" pin="!2CLR"/>
<wire x1="122.22" y1="-670.56" x2="117.14" y2="-670.56" width="0.1524" layer="91"/>
<label x="117.14" y="-670.05" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A11"/>
<wire x1="-17.78" y1="12.70" x2="-22.86" y2="12.70" width="0.1524" layer="91"/>
<label x="-22.86" y="13.21" size="1.778" layer="95"/></segment>
</net>
<net name="D0" class="0">
<segment><pinref part="U7" gate="G$1" pin="D1"/>
<wire x1="325.42" y1="-106.68" x2="320.34" y2="-106.68" width="0.1524" layer="91"/>
<label x="320.34" y="-106.17" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A3"/>
<wire x1="-17.78" y1="33.02" x2="-22.86" y2="33.02" width="0.1524" layer="91"/>
<label x="-22.86" y="33.53" size="1.778" layer="95"/></segment>
</net>
<net name="IRQ0" class="0">
<segment><pinref part="U7" gate="G$1" pin="Q1"/>
<wire x1="360.98" y1="-101.60" x2="366.06" y2="-101.60" width="0.1524" layer="91"/>
<label x="366.06" y="-101.09" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A0"/>
<wire x1="223.82" y1="-241.30" x2="218.74" y2="-241.30" width="0.1524" layer="91"/>
<label x="218.74" y="-240.79" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A0"/>
<wire x1="325.42" y1="-241.30" x2="320.34" y2="-241.30" width="0.1524" layer="91"/>
<label x="320.34" y="-240.79" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A0"/>
<wire x1="427.02" y1="-241.30" x2="421.94" y2="-241.30" width="0.1524" layer="91"/>
<label x="421.94" y="-240.79" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A0"/>
<wire x1="122.22" y1="-381.00" x2="117.14" y2="-381.00" width="0.1524" layer="91"/>
<label x="117.14" y="-380.49" size="1.778" layer="95"/></segment>
</net>
<net name="D1" class="0">
<segment><pinref part="U7" gate="G$1" pin="D2"/>
<wire x1="325.42" y1="-109.22" x2="320.34" y2="-109.22" width="0.1524" layer="91"/>
<label x="320.34" y="-108.71" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A4"/>
<wire x1="-17.78" y1="30.48" x2="-22.86" y2="30.48" width="0.1524" layer="91"/>
<label x="-22.86" y="30.99" size="1.778" layer="95"/></segment>
</net>
<net name="IRQ1" class="0">
<segment><pinref part="U7" gate="G$1" pin="Q2"/>
<wire x1="360.98" y1="-104.14" x2="366.06" y2="-104.14" width="0.1524" layer="91"/>
<label x="366.06" y="-103.63" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A1"/>
<wire x1="223.82" y1="-243.84" x2="218.74" y2="-243.84" width="0.1524" layer="91"/>
<label x="218.74" y="-243.33" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A1"/>
<wire x1="325.42" y1="-243.84" x2="320.34" y2="-243.84" width="0.1524" layer="91"/>
<label x="320.34" y="-243.33" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A1"/>
<wire x1="427.02" y1="-243.84" x2="421.94" y2="-243.84" width="0.1524" layer="91"/>
<label x="421.94" y="-243.33" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A1"/>
<wire x1="122.22" y1="-383.54" x2="117.14" y2="-383.54" width="0.1524" layer="91"/>
<label x="117.14" y="-383.03" size="1.778" layer="95"/></segment>
</net>
<net name="D2" class="0">
<segment><pinref part="U7" gate="G$1" pin="D3"/>
<wire x1="325.42" y1="-111.76" x2="320.34" y2="-111.76" width="0.1524" layer="91"/>
<label x="320.34" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A5"/>
<wire x1="-17.78" y1="27.94" x2="-22.86" y2="27.94" width="0.1524" layer="91"/>
<label x="-22.86" y="28.45" size="1.778" layer="95"/></segment>
</net>
<net name="IRQ2" class="0">
<segment><pinref part="U7" gate="G$1" pin="Q3"/>
<wire x1="360.98" y1="-106.68" x2="366.06" y2="-106.68" width="0.1524" layer="91"/>
<label x="366.06" y="-106.17" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A2"/>
<wire x1="223.82" y1="-246.38" x2="218.74" y2="-246.38" width="0.1524" layer="91"/>
<label x="218.74" y="-245.87" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A2"/>
<wire x1="325.42" y1="-246.38" x2="320.34" y2="-246.38" width="0.1524" layer="91"/>
<label x="320.34" y="-245.87" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A2"/>
<wire x1="427.02" y1="-246.38" x2="421.94" y2="-246.38" width="0.1524" layer="91"/>
<label x="421.94" y="-245.87" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A2"/>
<wire x1="122.22" y1="-386.08" x2="117.14" y2="-386.08" width="0.1524" layer="91"/>
<label x="117.14" y="-385.57" size="1.778" layer="95"/></segment>
</net>
<net name="D3" class="0">
<segment><pinref part="U7" gate="G$1" pin="D4"/>
<wire x1="325.42" y1="-114.30" x2="320.34" y2="-114.30" width="0.1524" layer="91"/>
<label x="320.34" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A6"/>
<wire x1="-17.78" y1="25.40" x2="-22.86" y2="25.40" width="0.1524" layer="91"/>
<label x="-22.86" y="25.91" size="1.778" layer="95"/></segment>
</net>
<net name="IRQ3" class="0">
<segment><pinref part="U7" gate="G$1" pin="Q4"/>
<wire x1="360.98" y1="-109.22" x2="366.06" y2="-109.22" width="0.1524" layer="91"/>
<label x="366.06" y="-108.71" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A3"/>
<wire x1="223.82" y1="-248.92" x2="218.74" y2="-248.92" width="0.1524" layer="91"/>
<label x="218.74" y="-248.41" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A3"/>
<wire x1="325.42" y1="-248.92" x2="320.34" y2="-248.92" width="0.1524" layer="91"/>
<label x="320.34" y="-248.41" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A3"/>
<wire x1="427.02" y1="-248.92" x2="421.94" y2="-248.92" width="0.1524" layer="91"/>
<label x="421.94" y="-248.41" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A3"/>
<wire x1="122.22" y1="-388.62" x2="117.14" y2="-388.62" width="0.1524" layer="91"/>
<label x="117.14" y="-388.11" size="1.778" layer="95"/></segment>
</net>
<net name="D4" class="0">
<segment><pinref part="U7" gate="G$1" pin="D5"/>
<wire x1="325.42" y1="-116.84" x2="320.34" y2="-116.84" width="0.1524" layer="91"/>
<label x="320.34" y="-116.33" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A7"/>
<wire x1="-17.78" y1="22.86" x2="-22.86" y2="22.86" width="0.1524" layer="91"/>
<label x="-22.86" y="23.37" size="1.778" layer="95"/></segment>
</net>
<net name="IRQ4" class="0">
<segment><pinref part="U7" gate="G$1" pin="Q5"/>
<wire x1="360.98" y1="-111.76" x2="366.06" y2="-111.76" width="0.1524" layer="91"/>
<label x="366.06" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A4"/>
<wire x1="223.82" y1="-251.46" x2="218.74" y2="-251.46" width="0.1524" layer="91"/>
<label x="218.74" y="-250.95" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A4"/>
<wire x1="325.42" y1="-251.46" x2="320.34" y2="-251.46" width="0.1524" layer="91"/>
<label x="320.34" y="-250.95" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A4"/>
<wire x1="427.02" y1="-251.46" x2="421.94" y2="-251.46" width="0.1524" layer="91"/>
<label x="421.94" y="-250.95" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A4"/>
<wire x1="122.22" y1="-391.16" x2="117.14" y2="-391.16" width="0.1524" layer="91"/>
<label x="117.14" y="-390.65" size="1.778" layer="95"/></segment>
</net>
<net name="D5" class="0">
<segment><pinref part="U7" gate="G$1" pin="D6"/>
<wire x1="325.42" y1="-119.38" x2="320.34" y2="-119.38" width="0.1524" layer="91"/>
<label x="320.34" y="-118.87" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A8"/>
<wire x1="-17.78" y1="20.32" x2="-22.86" y2="20.32" width="0.1524" layer="91"/>
<label x="-22.86" y="20.83" size="1.778" layer="95"/></segment>
</net>
<net name="IRQ5" class="0">
<segment><pinref part="U7" gate="G$1" pin="Q6"/>
<wire x1="360.98" y1="-114.30" x2="366.06" y2="-114.30" width="0.1524" layer="91"/>
<label x="366.06" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A5"/>
<wire x1="223.82" y1="-254.00" x2="218.74" y2="-254.00" width="0.1524" layer="91"/>
<label x="218.74" y="-253.49" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A5"/>
<wire x1="325.42" y1="-254.00" x2="320.34" y2="-254.00" width="0.1524" layer="91"/>
<label x="320.34" y="-253.49" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A5"/>
<wire x1="427.02" y1="-254.00" x2="421.94" y2="-254.00" width="0.1524" layer="91"/>
<label x="421.94" y="-253.49" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A5"/>
<wire x1="122.22" y1="-393.70" x2="117.14" y2="-393.70" width="0.1524" layer="91"/>
<label x="117.14" y="-393.19" size="1.778" layer="95"/></segment>
</net>
<net name="D6" class="0">
<segment><pinref part="U7" gate="G$1" pin="D7"/>
<wire x1="325.42" y1="-121.92" x2="320.34" y2="-121.92" width="0.1524" layer="91"/>
<label x="320.34" y="-121.41" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A9"/>
<wire x1="-17.78" y1="17.78" x2="-22.86" y2="17.78" width="0.1524" layer="91"/>
<label x="-22.86" y="18.29" size="1.778" layer="95"/></segment>
</net>
<net name="IRQ6" class="0">
<segment><pinref part="U7" gate="G$1" pin="Q7"/>
<wire x1="360.98" y1="-116.84" x2="366.06" y2="-116.84" width="0.1524" layer="91"/>
<label x="366.06" y="-116.33" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A6"/>
<wire x1="223.82" y1="-256.54" x2="218.74" y2="-256.54" width="0.1524" layer="91"/>
<label x="218.74" y="-256.03" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A6"/>
<wire x1="325.42" y1="-256.54" x2="320.34" y2="-256.54" width="0.1524" layer="91"/>
<label x="320.34" y="-256.03" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A6"/>
<wire x1="427.02" y1="-256.54" x2="421.94" y2="-256.54" width="0.1524" layer="91"/>
<label x="421.94" y="-256.03" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A6"/>
<wire x1="122.22" y1="-396.24" x2="117.14" y2="-396.24" width="0.1524" layer="91"/>
<label x="117.14" y="-395.73" size="1.778" layer="95"/></segment>
</net>
<net name="D7" class="0">
<segment><pinref part="U7" gate="G$1" pin="D8"/>
<wire x1="325.42" y1="-124.46" x2="320.34" y2="-124.46" width="0.1524" layer="91"/>
<label x="320.34" y="-123.95" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A10"/>
<wire x1="-17.78" y1="15.24" x2="-22.86" y2="15.24" width="0.1524" layer="91"/>
<label x="-22.86" y="15.75" size="1.778" layer="95"/></segment>
</net>
<net name="IRQ7" class="0">
<segment><pinref part="U7" gate="G$1" pin="Q8"/>
<wire x1="360.98" y1="-119.38" x2="366.06" y2="-119.38" width="0.1524" layer="91"/>
<label x="366.06" y="-118.87" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A7"/>
<wire x1="223.82" y1="-259.08" x2="218.74" y2="-259.08" width="0.1524" layer="91"/>
<label x="218.74" y="-258.57" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A7"/>
<wire x1="325.42" y1="-259.08" x2="320.34" y2="-259.08" width="0.1524" layer="91"/>
<label x="320.34" y="-258.57" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A7"/>
<wire x1="427.02" y1="-259.08" x2="421.94" y2="-259.08" width="0.1524" layer="91"/>
<label x="421.94" y="-258.57" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A7"/>
<wire x1="122.22" y1="-398.78" x2="117.14" y2="-398.78" width="0.1524" layer="91"/>
<label x="117.14" y="-398.27" size="1.778" layer="95"/></segment>
</net>
<net name="DLD0" class="0">
<segment><pinref part="U8" gate="G$1" pin="A"/>
<wire x1="427.02" y1="-101.60" x2="421.94" y2="-101.60" width="0.1524" layer="91"/>
<label x="421.94" y="-101.09" size="1.778" layer="95"/></segment>
<segment><pinref part="U14" gate="G$1" pin="Q5"/>
<wire x1="259.38" y1="-391.16" x2="264.46" y2="-391.16" width="0.1524" layer="91"/>
<label x="264.46" y="-390.65" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A16"/>
<wire x1="-17.78" y1="0.00" x2="-22.86" y2="0.00" width="0.1524" layer="91"/>
<label x="-22.86" y="0.51" size="1.778" layer="95"/></segment>
</net>
<net name="DLD1" class="0">
<segment><pinref part="U8" gate="G$1" pin="B"/>
<wire x1="427.02" y1="-104.14" x2="421.94" y2="-104.14" width="0.1524" layer="91"/>
<label x="421.94" y="-103.63" size="1.778" layer="95"/></segment>
<segment><pinref part="U14" gate="G$1" pin="Q6"/>
<wire x1="259.38" y1="-393.70" x2="264.46" y2="-393.70" width="0.1524" layer="91"/>
<label x="264.46" y="-393.19" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A17"/>
<wire x1="-17.78" y1="-2.54" x2="-22.86" y2="-2.54" width="0.1524" layer="91"/>
<label x="-22.86" y="-2.03" size="1.778" layer="95"/></segment>
</net>
<net name="DLD2" class="0">
<segment><pinref part="U8" gate="G$1" pin="C"/>
<wire x1="427.02" y1="-106.68" x2="421.94" y2="-106.68" width="0.1524" layer="91"/>
<label x="421.94" y="-106.17" size="1.778" layer="95"/></segment>
<segment><pinref part="U14" gate="G$1" pin="Q7"/>
<wire x1="259.38" y1="-396.24" x2="264.46" y2="-396.24" width="0.1524" layer="91"/>
<label x="264.46" y="-395.73" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A18"/>
<wire x1="-17.78" y1="-5.08" x2="-22.86" y2="-5.08" width="0.1524" layer="91"/>
<label x="-22.86" y="-4.57" size="1.778" layer="95"/></segment>
</net>
<net name="DLD3" class="0">
<segment><pinref part="U8" gate="G$1" pin="!G2A"/>
<wire x1="427.02" y1="-111.76" x2="421.94" y2="-111.76" width="0.1524" layer="91"/>
<label x="421.94" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="U14" gate="G$1" pin="Q8"/>
<wire x1="259.38" y1="-398.78" x2="264.46" y2="-398.78" width="0.1524" layer="91"/>
<label x="264.46" y="-398.27" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A19"/>
<wire x1="-17.78" y1="-7.62" x2="-22.86" y2="-7.62" width="0.1524" layer="91"/>
<label x="-22.86" y="-7.11" size="1.778" layer="95"/></segment>
</net>
<net name="-IRLD" class="0">
<segment><pinref part="U8" gate="G$1" pin="Y6"/>
<wire x1="462.58" y1="-116.84" x2="467.66" y2="-116.84" width="0.1524" layer="91"/>
<label x="467.66" y="-116.33" size="1.778" layer="95"/></segment>
<segment><pinref part="U7" gate="G$1" pin="!E"/>
<wire x1="325.42" y1="-101.60" x2="320.34" y2="-101.60" width="0.1524" layer="91"/>
<label x="320.34" y="-101.09" size="1.778" layer="95"/></segment>
</net>
<net name="SQ0" class="0">
<segment><pinref part="U18" gate="G$1" pin="QA"/>
<wire x1="259.38" y1="-520.70" x2="264.46" y2="-520.70" width="0.1524" layer="91"/>
<label x="264.46" y="-520.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A8"/>
<wire x1="223.82" y1="-261.62" x2="218.74" y2="-261.62" width="0.1524" layer="91"/>
<label x="218.74" y="-261.11" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A8"/>
<wire x1="325.42" y1="-261.62" x2="320.34" y2="-261.62" width="0.1524" layer="91"/>
<label x="320.34" y="-261.11" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A8"/>
<wire x1="427.02" y1="-261.62" x2="421.94" y2="-261.62" width="0.1524" layer="91"/>
<label x="421.94" y="-261.11" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A8"/>
<wire x1="122.22" y1="-401.32" x2="117.14" y2="-401.32" width="0.1524" layer="91"/>
<label x="117.14" y="-400.81" size="1.778" layer="95"/></segment>
</net>
<net name="SQ1" class="0">
<segment><pinref part="U18" gate="G$1" pin="QB"/>
<wire x1="259.38" y1="-523.24" x2="264.46" y2="-523.24" width="0.1524" layer="91"/>
<label x="264.46" y="-522.73" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A9"/>
<wire x1="223.82" y1="-264.16" x2="218.74" y2="-264.16" width="0.1524" layer="91"/>
<label x="218.74" y="-263.65" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A9"/>
<wire x1="325.42" y1="-264.16" x2="320.34" y2="-264.16" width="0.1524" layer="91"/>
<label x="320.34" y="-263.65" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A9"/>
<wire x1="427.02" y1="-264.16" x2="421.94" y2="-264.16" width="0.1524" layer="91"/>
<label x="421.94" y="-263.65" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A9"/>
<wire x1="122.22" y1="-403.86" x2="117.14" y2="-403.86" width="0.1524" layer="91"/>
<label x="117.14" y="-403.35" size="1.778" layer="95"/></segment>
</net>
<net name="SQ2" class="0">
<segment><pinref part="U18" gate="G$1" pin="QC"/>
<wire x1="259.38" y1="-525.78" x2="264.46" y2="-525.78" width="0.1524" layer="91"/>
<label x="264.46" y="-525.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A10"/>
<wire x1="223.82" y1="-266.70" x2="218.74" y2="-266.70" width="0.1524" layer="91"/>
<label x="218.74" y="-266.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A10"/>
<wire x1="325.42" y1="-266.70" x2="320.34" y2="-266.70" width="0.1524" layer="91"/>
<label x="320.34" y="-266.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A10"/>
<wire x1="427.02" y1="-266.70" x2="421.94" y2="-266.70" width="0.1524" layer="91"/>
<label x="421.94" y="-266.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A10"/>
<wire x1="122.22" y1="-406.40" x2="117.14" y2="-406.40" width="0.1524" layer="91"/>
<label x="117.14" y="-405.89" size="1.778" layer="95"/></segment>
</net>
<net name="SQ3" class="0">
<segment><pinref part="U18" gate="G$1" pin="QD"/>
<wire x1="259.38" y1="-528.32" x2="264.46" y2="-528.32" width="0.1524" layer="91"/>
<label x="264.46" y="-527.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A11"/>
<wire x1="223.82" y1="-269.24" x2="218.74" y2="-269.24" width="0.1524" layer="91"/>
<label x="218.74" y="-268.73" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A11"/>
<wire x1="325.42" y1="-269.24" x2="320.34" y2="-269.24" width="0.1524" layer="91"/>
<label x="320.34" y="-268.73" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A11"/>
<wire x1="427.02" y1="-269.24" x2="421.94" y2="-269.24" width="0.1524" layer="91"/>
<label x="421.94" y="-268.73" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A11"/>
<wire x1="122.22" y1="-408.94" x2="117.14" y2="-408.94" width="0.1524" layer="91"/>
<label x="117.14" y="-408.43" size="1.778" layer="95"/></segment>
</net>
<net name="CONDY" class="0">
<segment><pinref part="U9" gate="G$1" pin="Y"/>
<wire x1="157.78" y1="-241.30" x2="162.86" y2="-241.30" width="0.1524" layer="91"/>
<label x="162.86" y="-240.79" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="A12"/>
<wire x1="223.82" y1="-271.78" x2="218.74" y2="-271.78" width="0.1524" layer="91"/>
<label x="218.74" y="-271.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="A12"/>
<wire x1="325.42" y1="-271.78" x2="320.34" y2="-271.78" width="0.1524" layer="91"/>
<label x="320.34" y="-271.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="A12"/>
<wire x1="427.02" y1="-271.78" x2="421.94" y2="-271.78" width="0.1524" layer="91"/>
<label x="421.94" y="-271.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="A12"/>
<wire x1="122.22" y1="-411.48" x2="117.14" y2="-411.48" width="0.1524" layer="91"/>
<label x="117.14" y="-410.97" size="1.778" layer="95"/></segment>
</net>
<net name="FC" class="0">
<segment><pinref part="U9" gate="G$1" pin="D2"/>
<wire x1="122.22" y1="-254.00" x2="117.14" y2="-254.00" width="0.1524" layer="91"/>
<label x="117.14" y="-253.49" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A27"/>
<wire x1="-17.78" y1="-27.94" x2="-22.86" y2="-27.94" width="0.1524" layer="91"/>
<label x="-22.86" y="-27.43" size="1.778" layer="95"/></segment>
</net>
<net name="FZ" class="0">
<segment><pinref part="U9" gate="G$1" pin="D3"/>
<wire x1="122.22" y1="-256.54" x2="117.14" y2="-256.54" width="0.1524" layer="91"/>
<label x="117.14" y="-256.03" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="4B"/>
<wire x1="223.82" y1="-119.38" x2="218.74" y2="-119.38" width="0.1524" layer="91"/>
<label x="218.74" y="-118.87" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A28"/>
<wire x1="-17.78" y1="-30.48" x2="-22.86" y2="-30.48" width="0.1524" layer="91"/>
<label x="-22.86" y="-29.97" size="1.778" layer="95"/></segment>
</net>
<net name="FN" class="0">
<segment><pinref part="U9" gate="G$1" pin="D4"/>
<wire x1="122.22" y1="-259.08" x2="117.14" y2="-259.08" width="0.1524" layer="91"/>
<label x="117.14" y="-258.57" size="1.778" layer="95"/></segment>
<segment><pinref part="U19" gate="G$1" pin="1A"/>
<wire x1="325.42" y1="-520.70" x2="320.34" y2="-520.70" width="0.1524" layer="91"/>
<label x="320.34" y="-520.19" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A29"/>
<wire x1="-17.78" y1="-33.02" x2="-22.86" y2="-33.02" width="0.1524" layer="91"/>
<label x="-22.86" y="-32.51" size="1.778" layer="95"/></segment>
</net>
<net name="FV" class="0">
<segment><pinref part="U9" gate="G$1" pin="D5"/>
<wire x1="122.22" y1="-261.62" x2="117.14" y2="-261.62" width="0.1524" layer="91"/>
<label x="117.14" y="-261.11" size="1.778" layer="95"/></segment>
<segment><pinref part="U19" gate="G$1" pin="1B"/>
<wire x1="325.42" y1="-523.24" x2="320.34" y2="-523.24" width="0.1524" layer="91"/>
<label x="320.34" y="-522.73" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A30"/>
<wire x1="-17.78" y1="-35.56" x2="-22.86" y2="-35.56" width="0.1524" layer="91"/>
<label x="-22.86" y="-35.05" size="1.778" layer="95"/></segment>
</net>
<net name="NV" class="0">
<segment><pinref part="U19" gate="G$1" pin="1Y"/>
<wire x1="360.98" y1="-520.70" x2="366.06" y2="-520.70" width="0.1524" layer="91"/>
<label x="366.06" y="-520.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U9" gate="G$1" pin="D6"/>
<wire x1="122.22" y1="-264.16" x2="117.14" y2="-264.16" width="0.1524" layer="91"/>
<label x="117.14" y="-263.65" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="4A"/>
<wire x1="223.82" y1="-116.84" x2="218.74" y2="-116.84" width="0.1524" layer="91"/>
<label x="218.74" y="-116.33" size="1.778" layer="95"/></segment>
</net>
<net name="NVZ" class="0">
<segment><pinref part="U6" gate="G$1" pin="4Y"/>
<wire x1="259.38" y1="-109.22" x2="264.46" y2="-109.22" width="0.1524" layer="91"/>
<label x="264.46" y="-108.71" size="1.778" layer="95"/></segment>
<segment><pinref part="U9" gate="G$1" pin="D7"/>
<wire x1="122.22" y1="-266.70" x2="117.14" y2="-266.70" width="0.1524" layer="91"/>
<label x="117.14" y="-266.19" size="1.778" layer="95"/></segment>
</net>
<net name="IRQ" class="0">
<segment><pinref part="U21" gate="G$1" pin="1D"/>
<wire x1="122.22" y1="-662.94" x2="117.14" y2="-662.94" width="0.1524" layer="91"/>
<label x="117.14" y="-662.43" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B29"/>
<wire x1="-17.78" y1="-114.30" x2="-22.86" y2="-114.30" width="0.1524" layer="91"/>
<label x="-22.86" y="-113.79" size="1.778" layer="95"/></segment>
</net>
<net name="P14B0" class="0">
<segment><pinref part="U14" gate="G$1" pin="D1"/>
<wire x1="223.82" y1="-386.08" x2="218.74" y2="-386.08" width="0.1524" layer="91"/>
<label x="218.74" y="-385.57" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="IO0"/>
<wire x1="259.38" y1="-241.30" x2="264.46" y2="-241.30" width="0.1524" layer="91"/>
<label x="264.46" y="-240.79" size="1.778" layer="95"/></segment>
</net>
<net name="DOE0" class="0">
<segment><pinref part="U14" gate="G$1" pin="Q1"/>
<wire x1="259.38" y1="-381.00" x2="264.46" y2="-381.00" width="0.1524" layer="91"/>
<label x="264.46" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A12"/>
<wire x1="-17.78" y1="10.16" x2="-22.86" y2="10.16" width="0.1524" layer="91"/>
<label x="-22.86" y="10.67" size="1.778" layer="95"/></segment>
</net>
<net name="P14B1" class="0">
<segment><pinref part="U14" gate="G$1" pin="D2"/>
<wire x1="223.82" y1="-388.62" x2="218.74" y2="-388.62" width="0.1524" layer="91"/>
<label x="218.74" y="-388.11" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="IO1"/>
<wire x1="259.38" y1="-243.84" x2="264.46" y2="-243.84" width="0.1524" layer="91"/>
<label x="264.46" y="-243.33" size="1.778" layer="95"/></segment>
</net>
<net name="DOE1" class="0">
<segment><pinref part="U14" gate="G$1" pin="Q2"/>
<wire x1="259.38" y1="-383.54" x2="264.46" y2="-383.54" width="0.1524" layer="91"/>
<label x="264.46" y="-383.03" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A13"/>
<wire x1="-17.78" y1="7.62" x2="-22.86" y2="7.62" width="0.1524" layer="91"/>
<label x="-22.86" y="8.13" size="1.778" layer="95"/></segment>
</net>
<net name="P14B2" class="0">
<segment><pinref part="U14" gate="G$1" pin="D3"/>
<wire x1="223.82" y1="-391.16" x2="218.74" y2="-391.16" width="0.1524" layer="91"/>
<label x="218.74" y="-390.65" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="IO2"/>
<wire x1="259.38" y1="-246.38" x2="264.46" y2="-246.38" width="0.1524" layer="91"/>
<label x="264.46" y="-245.87" size="1.778" layer="95"/></segment>
</net>
<net name="DOE2" class="0">
<segment><pinref part="U14" gate="G$1" pin="Q3"/>
<wire x1="259.38" y1="-386.08" x2="264.46" y2="-386.08" width="0.1524" layer="91"/>
<label x="264.46" y="-385.57" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A14"/>
<wire x1="-17.78" y1="5.08" x2="-22.86" y2="5.08" width="0.1524" layer="91"/>
<label x="-22.86" y="5.59" size="1.778" layer="95"/></segment>
</net>
<net name="P14B3" class="0">
<segment><pinref part="U14" gate="G$1" pin="D4"/>
<wire x1="223.82" y1="-393.70" x2="218.74" y2="-393.70" width="0.1524" layer="91"/>
<label x="218.74" y="-393.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="IO3"/>
<wire x1="259.38" y1="-248.92" x2="264.46" y2="-248.92" width="0.1524" layer="91"/>
<label x="264.46" y="-248.41" size="1.778" layer="95"/></segment>
</net>
<net name="DOE3" class="0">
<segment><pinref part="U14" gate="G$1" pin="Q4"/>
<wire x1="259.38" y1="-388.62" x2="264.46" y2="-388.62" width="0.1524" layer="91"/>
<label x="264.46" y="-388.11" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A15"/>
<wire x1="-17.78" y1="2.54" x2="-22.86" y2="2.54" width="0.1524" layer="91"/>
<label x="-22.86" y="3.05" size="1.778" layer="95"/></segment>
</net>
<net name="P14B4" class="0">
<segment><pinref part="U14" gate="G$1" pin="D5"/>
<wire x1="223.82" y1="-396.24" x2="218.74" y2="-396.24" width="0.1524" layer="91"/>
<label x="218.74" y="-395.73" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="IO4"/>
<wire x1="259.38" y1="-251.46" x2="264.46" y2="-251.46" width="0.1524" layer="91"/>
<label x="264.46" y="-250.95" size="1.778" layer="95"/></segment>
</net>
<net name="P14B5" class="0">
<segment><pinref part="U14" gate="G$1" pin="D6"/>
<wire x1="223.82" y1="-398.78" x2="218.74" y2="-398.78" width="0.1524" layer="91"/>
<label x="218.74" y="-398.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="IO5"/>
<wire x1="259.38" y1="-254.00" x2="264.46" y2="-254.00" width="0.1524" layer="91"/>
<label x="264.46" y="-253.49" size="1.778" layer="95"/></segment>
</net>
<net name="P14B6" class="0">
<segment><pinref part="U14" gate="G$1" pin="D7"/>
<wire x1="223.82" y1="-401.32" x2="218.74" y2="-401.32" width="0.1524" layer="91"/>
<label x="218.74" y="-400.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="IO6"/>
<wire x1="259.38" y1="-256.54" x2="264.46" y2="-256.54" width="0.1524" layer="91"/>
<label x="264.46" y="-256.03" size="1.778" layer="95"/></segment>
</net>
<net name="P14B7" class="0">
<segment><pinref part="U14" gate="G$1" pin="D8"/>
<wire x1="223.82" y1="-403.86" x2="218.74" y2="-403.86" width="0.1524" layer="91"/>
<label x="218.74" y="-403.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U10" gate="G$1" pin="IO7"/>
<wire x1="259.38" y1="-259.08" x2="264.46" y2="-259.08" width="0.1524" layer="91"/>
<label x="264.46" y="-258.57" size="1.778" layer="95"/></segment>
</net>
<net name="P15B0" class="0">
<segment><pinref part="U15" gate="G$1" pin="D1"/>
<wire x1="325.42" y1="-386.08" x2="320.34" y2="-386.08" width="0.1524" layer="91"/>
<label x="320.34" y="-385.57" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="IO0"/>
<wire x1="360.98" y1="-241.30" x2="366.06" y2="-241.30" width="0.1524" layer="91"/>
<label x="366.06" y="-240.79" size="1.778" layer="95"/></segment>
</net>
<net name="PSEL0" class="0">
<segment><pinref part="U15" gate="G$1" pin="Q1"/>
<wire x1="360.98" y1="-381.00" x2="366.06" y2="-381.00" width="0.1524" layer="91"/>
<label x="366.06" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A20"/>
<wire x1="-17.78" y1="-10.16" x2="-22.86" y2="-10.16" width="0.1524" layer="91"/>
<label x="-22.86" y="-9.65" size="1.778" layer="95"/></segment>
</net>
<net name="P15B1" class="0">
<segment><pinref part="U15" gate="G$1" pin="D2"/>
<wire x1="325.42" y1="-388.62" x2="320.34" y2="-388.62" width="0.1524" layer="91"/>
<label x="320.34" y="-388.11" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="IO1"/>
<wire x1="360.98" y1="-243.84" x2="366.06" y2="-243.84" width="0.1524" layer="91"/>
<label x="366.06" y="-243.33" size="1.778" layer="95"/></segment>
</net>
<net name="PSEL1" class="0">
<segment><pinref part="U15" gate="G$1" pin="Q2"/>
<wire x1="360.98" y1="-383.54" x2="366.06" y2="-383.54" width="0.1524" layer="91"/>
<label x="366.06" y="-383.03" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A21"/>
<wire x1="-17.78" y1="-12.70" x2="-22.86" y2="-12.70" width="0.1524" layer="91"/>
<label x="-22.86" y="-12.19" size="1.778" layer="95"/></segment>
</net>
<net name="P15B2" class="0">
<segment><pinref part="U15" gate="G$1" pin="D3"/>
<wire x1="325.42" y1="-391.16" x2="320.34" y2="-391.16" width="0.1524" layer="91"/>
<label x="320.34" y="-390.65" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="IO2"/>
<wire x1="360.98" y1="-246.38" x2="366.06" y2="-246.38" width="0.1524" layer="91"/>
<label x="366.06" y="-245.87" size="1.778" layer="95"/></segment>
</net>
<net name="PSEL2" class="0">
<segment><pinref part="U15" gate="G$1" pin="Q3"/>
<wire x1="360.98" y1="-386.08" x2="366.06" y2="-386.08" width="0.1524" layer="91"/>
<label x="366.06" y="-385.57" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C27"/>
<wire x1="17.78" y1="-27.94" x2="22.86" y2="-27.94" width="0.1524" layer="91"/>
<label x="22.86" y="-27.43" size="1.778" layer="95"/></segment>
</net>
<net name="P15B3" class="0">
<segment><pinref part="U15" gate="G$1" pin="D4"/>
<wire x1="325.42" y1="-393.70" x2="320.34" y2="-393.70" width="0.1524" layer="91"/>
<label x="320.34" y="-393.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="IO3"/>
<wire x1="360.98" y1="-248.92" x2="366.06" y2="-248.92" width="0.1524" layer="91"/>
<label x="366.06" y="-248.41" size="1.778" layer="95"/></segment>
</net>
<net name="PINC" class="0">
<segment><pinref part="U15" gate="G$1" pin="Q4"/>
<wire x1="360.98" y1="-388.62" x2="366.06" y2="-388.62" width="0.1524" layer="91"/>
<label x="366.06" y="-388.11" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A22"/>
<wire x1="-17.78" y1="-15.24" x2="-22.86" y2="-15.24" width="0.1524" layer="91"/>
<label x="-22.86" y="-14.73" size="1.778" layer="95"/></segment>
</net>
<net name="P15B4" class="0">
<segment><pinref part="U15" gate="G$1" pin="D5"/>
<wire x1="325.42" y1="-396.24" x2="320.34" y2="-396.24" width="0.1524" layer="91"/>
<label x="320.34" y="-395.73" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="IO4"/>
<wire x1="360.98" y1="-251.46" x2="366.06" y2="-251.46" width="0.1524" layer="91"/>
<label x="366.06" y="-250.95" size="1.778" layer="95"/></segment>
</net>
<net name="PDEC" class="0">
<segment><pinref part="U15" gate="G$1" pin="Q5"/>
<wire x1="360.98" y1="-391.16" x2="366.06" y2="-391.16" width="0.1524" layer="91"/>
<label x="366.06" y="-390.65" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A23"/>
<wire x1="-17.78" y1="-17.78" x2="-22.86" y2="-17.78" width="0.1524" layer="91"/>
<label x="-22.86" y="-17.27" size="1.778" layer="95"/></segment>
</net>
<net name="P15B5" class="0">
<segment><pinref part="U15" gate="G$1" pin="D6"/>
<wire x1="325.42" y1="-398.78" x2="320.34" y2="-398.78" width="0.1524" layer="91"/>
<label x="320.34" y="-398.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="IO5"/>
<wire x1="360.98" y1="-254.00" x2="366.06" y2="-254.00" width="0.1524" layer="91"/>
<label x="366.06" y="-253.49" size="1.778" layer="95"/></segment>
</net>
<net name="ALUS0" class="0">
<segment><pinref part="U15" gate="G$1" pin="Q6"/>
<wire x1="360.98" y1="-393.70" x2="366.06" y2="-393.70" width="0.1524" layer="91"/>
<label x="366.06" y="-393.19" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C19"/>
<wire x1="17.78" y1="-7.62" x2="22.86" y2="-7.62" width="0.1524" layer="91"/>
<label x="22.86" y="-7.11" size="1.778" layer="95"/></segment>
</net>
<net name="P15B6" class="0">
<segment><pinref part="U15" gate="G$1" pin="D7"/>
<wire x1="325.42" y1="-401.32" x2="320.34" y2="-401.32" width="0.1524" layer="91"/>
<label x="320.34" y="-400.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="IO6"/>
<wire x1="360.98" y1="-256.54" x2="366.06" y2="-256.54" width="0.1524" layer="91"/>
<label x="366.06" y="-256.03" size="1.778" layer="95"/></segment>
</net>
<net name="ALUS1" class="0">
<segment><pinref part="U15" gate="G$1" pin="Q7"/>
<wire x1="360.98" y1="-396.24" x2="366.06" y2="-396.24" width="0.1524" layer="91"/>
<label x="366.06" y="-395.73" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C20"/>
<wire x1="17.78" y1="-10.16" x2="22.86" y2="-10.16" width="0.1524" layer="91"/>
<label x="22.86" y="-9.65" size="1.778" layer="95"/></segment>
</net>
<net name="P15B7" class="0">
<segment><pinref part="U15" gate="G$1" pin="D8"/>
<wire x1="325.42" y1="-403.86" x2="320.34" y2="-403.86" width="0.1524" layer="91"/>
<label x="320.34" y="-403.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U11" gate="G$1" pin="IO7"/>
<wire x1="360.98" y1="-259.08" x2="366.06" y2="-259.08" width="0.1524" layer="91"/>
<label x="366.06" y="-258.57" size="1.778" layer="95"/></segment>
</net>
<net name="ALUS2" class="0">
<segment><pinref part="U15" gate="G$1" pin="Q8"/>
<wire x1="360.98" y1="-398.78" x2="366.06" y2="-398.78" width="0.1524" layer="91"/>
<label x="366.06" y="-398.27" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C21"/>
<wire x1="17.78" y1="-12.70" x2="22.86" y2="-12.70" width="0.1524" layer="91"/>
<label x="22.86" y="-12.19" size="1.778" layer="95"/></segment>
</net>
<net name="P16B0" class="0">
<segment><pinref part="U16" gate="G$1" pin="D1"/>
<wire x1="427.02" y1="-386.08" x2="421.94" y2="-386.08" width="0.1524" layer="91"/>
<label x="421.94" y="-385.57" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="IO0"/>
<wire x1="462.58" y1="-241.30" x2="467.66" y2="-241.30" width="0.1524" layer="91"/>
<label x="467.66" y="-240.79" size="1.778" layer="95"/></segment>
</net>
<net name="ALUS3" class="0">
<segment><pinref part="U16" gate="G$1" pin="Q1"/>
<wire x1="462.58" y1="-381.00" x2="467.66" y2="-381.00" width="0.1524" layer="91"/>
<label x="467.66" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C22"/>
<wire x1="17.78" y1="-15.24" x2="22.86" y2="-15.24" width="0.1524" layer="91"/>
<label x="22.86" y="-14.73" size="1.778" layer="95"/></segment>
</net>
<net name="P16B1" class="0">
<segment><pinref part="U16" gate="G$1" pin="D2"/>
<wire x1="427.02" y1="-388.62" x2="421.94" y2="-388.62" width="0.1524" layer="91"/>
<label x="421.94" y="-388.11" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="IO1"/>
<wire x1="462.58" y1="-243.84" x2="467.66" y2="-243.84" width="0.1524" layer="91"/>
<label x="467.66" y="-243.33" size="1.778" layer="95"/></segment>
</net>
<net name="ALUM" class="0">
<segment><pinref part="U16" gate="G$1" pin="Q2"/>
<wire x1="462.58" y1="-383.54" x2="467.66" y2="-383.54" width="0.1524" layer="91"/>
<label x="467.66" y="-383.03" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C23"/>
<wire x1="17.78" y1="-17.78" x2="22.86" y2="-17.78" width="0.1524" layer="91"/>
<label x="22.86" y="-17.27" size="1.778" layer="95"/></segment>
</net>
<net name="P16B2" class="0">
<segment><pinref part="U16" gate="G$1" pin="D3"/>
<wire x1="427.02" y1="-391.16" x2="421.94" y2="-391.16" width="0.1524" layer="91"/>
<label x="421.94" y="-390.65" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="IO2"/>
<wire x1="462.58" y1="-246.38" x2="467.66" y2="-246.38" width="0.1524" layer="91"/>
<label x="467.66" y="-245.87" size="1.778" layer="95"/></segment>
</net>
<net name="CIN" class="0">
<segment><pinref part="U16" gate="G$1" pin="Q3"/>
<wire x1="462.58" y1="-386.08" x2="467.66" y2="-386.08" width="0.1524" layer="91"/>
<label x="467.66" y="-385.57" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C24"/>
<wire x1="17.78" y1="-20.32" x2="22.86" y2="-20.32" width="0.1524" layer="91"/>
<label x="22.86" y="-19.81" size="1.778" layer="95"/></segment>
</net>
<net name="P16B3" class="0">
<segment><pinref part="U16" gate="G$1" pin="D4"/>
<wire x1="427.02" y1="-393.70" x2="421.94" y2="-393.70" width="0.1524" layer="91"/>
<label x="421.94" y="-393.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="IO3"/>
<wire x1="462.58" y1="-248.92" x2="467.66" y2="-248.92" width="0.1524" layer="91"/>
<label x="467.66" y="-248.41" size="1.778" layer="95"/></segment>
</net>
<net name="SH0" class="0">
<segment><pinref part="U16" gate="G$1" pin="Q4"/>
<wire x1="462.58" y1="-388.62" x2="467.66" y2="-388.62" width="0.1524" layer="91"/>
<label x="467.66" y="-388.11" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C25"/>
<wire x1="17.78" y1="-22.86" x2="22.86" y2="-22.86" width="0.1524" layer="91"/>
<label x="22.86" y="-22.35" size="1.778" layer="95"/></segment>
</net>
<net name="P16B4" class="0">
<segment><pinref part="U16" gate="G$1" pin="D5"/>
<wire x1="427.02" y1="-396.24" x2="421.94" y2="-396.24" width="0.1524" layer="91"/>
<label x="421.94" y="-395.73" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="IO4"/>
<wire x1="462.58" y1="-251.46" x2="467.66" y2="-251.46" width="0.1524" layer="91"/>
<label x="467.66" y="-250.95" size="1.778" layer="95"/></segment>
</net>
<net name="SH1" class="0">
<segment><pinref part="U16" gate="G$1" pin="Q5"/>
<wire x1="462.58" y1="-391.16" x2="467.66" y2="-391.16" width="0.1524" layer="91"/>
<label x="467.66" y="-390.65" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C26"/>
<wire x1="17.78" y1="-25.40" x2="22.86" y2="-25.40" width="0.1524" layer="91"/>
<label x="22.86" y="-24.89" size="1.778" layer="95"/></segment>
</net>
<net name="P16B5" class="0">
<segment><pinref part="U16" gate="G$1" pin="D6"/>
<wire x1="427.02" y1="-398.78" x2="421.94" y2="-398.78" width="0.1524" layer="91"/>
<label x="421.94" y="-398.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="IO5"/>
<wire x1="462.58" y1="-254.00" x2="467.66" y2="-254.00" width="0.1524" layer="91"/>
<label x="467.66" y="-253.49" size="1.778" layer="95"/></segment>
</net>
<net name="LDF" class="0">
<segment><pinref part="U16" gate="G$1" pin="Q6"/>
<wire x1="462.58" y1="-393.70" x2="467.66" y2="-393.70" width="0.1524" layer="91"/>
<label x="467.66" y="-393.19" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A26"/>
<wire x1="-17.78" y1="-25.40" x2="-22.86" y2="-25.40" width="0.1524" layer="91"/>
<label x="-22.86" y="-24.89" size="1.778" layer="95"/></segment>
</net>
<net name="P16B6" class="0">
<segment><pinref part="U16" gate="G$1" pin="D7"/>
<wire x1="427.02" y1="-401.32" x2="421.94" y2="-401.32" width="0.1524" layer="91"/>
<label x="421.94" y="-400.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="IO6"/>
<wire x1="462.58" y1="-256.54" x2="467.66" y2="-256.54" width="0.1524" layer="91"/>
<label x="467.66" y="-256.03" size="1.778" layer="95"/></segment>
</net>
<net name="FCOND0" class="0">
<segment><pinref part="U16" gate="G$1" pin="Q7"/>
<wire x1="462.58" y1="-396.24" x2="467.66" y2="-396.24" width="0.1524" layer="91"/>
<label x="467.66" y="-395.73" size="1.778" layer="95"/></segment>
<segment><pinref part="U9" gate="G$1" pin="A"/>
<wire x1="122.22" y1="-241.30" x2="117.14" y2="-241.30" width="0.1524" layer="91"/>
<label x="117.14" y="-240.79" size="1.778" layer="95"/></segment>
</net>
<net name="P16B7" class="0">
<segment><pinref part="U16" gate="G$1" pin="D8"/>
<wire x1="427.02" y1="-403.86" x2="421.94" y2="-403.86" width="0.1524" layer="91"/>
<label x="421.94" y="-403.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U12" gate="G$1" pin="IO7"/>
<wire x1="462.58" y1="-259.08" x2="467.66" y2="-259.08" width="0.1524" layer="91"/>
<label x="467.66" y="-258.57" size="1.778" layer="95"/></segment>
</net>
<net name="FCOND1" class="0">
<segment><pinref part="U16" gate="G$1" pin="Q8"/>
<wire x1="462.58" y1="-398.78" x2="467.66" y2="-398.78" width="0.1524" layer="91"/>
<label x="467.66" y="-398.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U9" gate="G$1" pin="B"/>
<wire x1="122.22" y1="-243.84" x2="117.14" y2="-243.84" width="0.1524" layer="91"/>
<label x="117.14" y="-243.33" size="1.778" layer="95"/></segment>
</net>
<net name="P17B0" class="0">
<segment><pinref part="U17" gate="G$1" pin="D1"/>
<wire x1="122.22" y1="-525.78" x2="117.14" y2="-525.78" width="0.1524" layer="91"/>
<label x="117.14" y="-525.27" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="IO0"/>
<wire x1="157.78" y1="-381.00" x2="162.86" y2="-381.00" width="0.1524" layer="91"/>
<label x="162.86" y="-380.49" size="1.778" layer="95"/></segment>
</net>
<net name="FCOND2" class="0">
<segment><pinref part="U17" gate="G$1" pin="Q1"/>
<wire x1="157.78" y1="-520.70" x2="162.86" y2="-520.70" width="0.1524" layer="91"/>
<label x="162.86" y="-520.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U9" gate="G$1" pin="C"/>
<wire x1="122.22" y1="-246.38" x2="117.14" y2="-246.38" width="0.1524" layer="91"/>
<label x="117.14" y="-245.87" size="1.778" layer="95"/></segment>
</net>
<net name="P17B1" class="0">
<segment><pinref part="U17" gate="G$1" pin="D2"/>
<wire x1="122.22" y1="-528.32" x2="117.14" y2="-528.32" width="0.1524" layer="91"/>
<label x="117.14" y="-527.81" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="IO1"/>
<wire x1="157.78" y1="-383.54" x2="162.86" y2="-383.54" width="0.1524" layer="91"/>
<label x="162.86" y="-383.03" size="1.778" layer="95"/></segment>
</net>
<net name="URST" class="0">
<segment><pinref part="U17" gate="G$1" pin="Q2"/>
<wire x1="157.78" y1="-523.24" x2="162.86" y2="-523.24" width="0.1524" layer="91"/>
<label x="162.86" y="-522.73" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="2A"/>
<wire x1="427.02" y1="33.02" x2="421.94" y2="33.02" width="0.1524" layer="91"/>
<label x="421.94" y="33.53" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="2B"/>
<wire x1="427.02" y1="30.48" x2="421.94" y2="30.48" width="0.1524" layer="91"/>
<label x="421.94" y="30.99" size="1.778" layer="95"/></segment>
</net>
<net name="P17B2" class="0">
<segment><pinref part="U17" gate="G$1" pin="D3"/>
<wire x1="122.22" y1="-530.86" x2="117.14" y2="-530.86" width="0.1524" layer="91"/>
<label x="117.14" y="-530.35" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="IO2"/>
<wire x1="157.78" y1="-386.08" x2="162.86" y2="-386.08" width="0.1524" layer="91"/>
<label x="162.86" y="-385.57" size="1.778" layer="95"/></segment>
</net>
<net name="P17B3" class="0">
<segment><pinref part="U17" gate="G$1" pin="D4"/>
<wire x1="122.22" y1="-533.40" x2="117.14" y2="-533.40" width="0.1524" layer="91"/>
<label x="117.14" y="-532.89" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="IO3"/>
<wire x1="157.78" y1="-388.62" x2="162.86" y2="-388.62" width="0.1524" layer="91"/>
<label x="162.86" y="-388.11" size="1.778" layer="95"/></segment>
</net>
<net name="LDZN" class="0">
<segment><pinref part="U17" gate="G$1" pin="Q4"/>
<wire x1="157.78" y1="-528.32" x2="162.86" y2="-528.32" width="0.1524" layer="91"/>
<label x="162.86" y="-527.81" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C28"/>
<wire x1="17.78" y1="-30.48" x2="22.86" y2="-30.48" width="0.1524" layer="91"/>
<label x="22.86" y="-29.97" size="1.778" layer="95"/></segment>
</net>
<net name="P17B4" class="0">
<segment><pinref part="U17" gate="G$1" pin="D5"/>
<wire x1="122.22" y1="-535.94" x2="117.14" y2="-535.94" width="0.1524" layer="91"/>
<label x="117.14" y="-535.43" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="IO4"/>
<wire x1="157.78" y1="-391.16" x2="162.86" y2="-391.16" width="0.1524" layer="91"/>
<label x="162.86" y="-390.65" size="1.778" layer="95"/></segment>
</net>
<net name="SHCIN" class="0">
<segment><pinref part="U17" gate="G$1" pin="Q5"/>
<wire x1="157.78" y1="-530.86" x2="162.86" y2="-530.86" width="0.1524" layer="91"/>
<label x="162.86" y="-530.35" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C29"/>
<wire x1="17.78" y1="-33.02" x2="22.86" y2="-33.02" width="0.1524" layer="91"/>
<label x="22.86" y="-32.51" size="1.778" layer="95"/></segment>
</net>
<net name="P17B5" class="0">
<segment><pinref part="U17" gate="G$1" pin="D6"/>
<wire x1="122.22" y1="-538.48" x2="117.14" y2="-538.48" width="0.1524" layer="91"/>
<label x="117.14" y="-537.97" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="IO5"/>
<wire x1="157.78" y1="-393.70" x2="162.86" y2="-393.70" width="0.1524" layer="91"/>
<label x="162.86" y="-393.19" size="1.778" layer="95"/></segment>
</net>
<net name="SETC" class="0">
<segment><pinref part="U17" gate="G$1" pin="Q6"/>
<wire x1="157.78" y1="-533.40" x2="162.86" y2="-533.40" width="0.1524" layer="91"/>
<label x="162.86" y="-532.89" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C30"/>
<wire x1="17.78" y1="-35.56" x2="22.86" y2="-35.56" width="0.1524" layer="91"/>
<label x="22.86" y="-35.05" size="1.778" layer="95"/></segment>
</net>
<net name="P17B6" class="0">
<segment><pinref part="U17" gate="G$1" pin="D7"/>
<wire x1="122.22" y1="-541.02" x2="117.14" y2="-541.02" width="0.1524" layer="91"/>
<label x="117.14" y="-540.51" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="IO6"/>
<wire x1="157.78" y1="-396.24" x2="162.86" y2="-396.24" width="0.1524" layer="91"/>
<label x="162.86" y="-395.73" size="1.778" layer="95"/></segment>
</net>
<net name="CLRC" class="0">
<segment><pinref part="U17" gate="G$1" pin="Q7"/>
<wire x1="157.78" y1="-535.94" x2="162.86" y2="-535.94" width="0.1524" layer="91"/>
<label x="162.86" y="-535.43" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B27"/>
<wire x1="-17.78" y1="-109.22" x2="-22.86" y2="-109.22" width="0.1524" layer="91"/>
<label x="-22.86" y="-108.71" size="1.778" layer="95"/></segment>
</net>
<net name="P17B7" class="0">
<segment><pinref part="U17" gate="G$1" pin="D8"/>
<wire x1="122.22" y1="-543.56" x2="117.14" y2="-543.56" width="0.1524" layer="91"/>
<label x="117.14" y="-543.05" size="1.778" layer="95"/></segment>
<segment><pinref part="U13" gate="G$1" pin="IO7"/>
<wire x1="157.78" y1="-398.78" x2="162.86" y2="-398.78" width="0.1524" layer="91"/>
<label x="162.86" y="-398.27" size="1.778" layer="95"/></segment>
</net>
<net name="BSEL" class="0">
<segment><pinref part="U17" gate="G$1" pin="Q8"/>
<wire x1="157.78" y1="-538.48" x2="162.86" y2="-538.48" width="0.1524" layer="91"/>
<label x="162.86" y="-537.97" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="B28"/>
<wire x1="-17.78" y1="-111.76" x2="-22.86" y2="-111.76" width="0.1524" layer="91"/>
<label x="-22.86" y="-111.25" size="1.778" layer="95"/></segment>
</net>
<net name="-USTL" class="0">
<segment><pinref part="U4" gate="G$1" pin="2Y"/>
<wire x1="462.58" y1="35.56" x2="467.66" y2="35.56" width="0.1524" layer="91"/>
<label x="467.66" y="36.07" size="1.778" layer="95"/></segment>
<segment><pinref part="U18" gate="G$1" pin="!LOAD"/>
<wire x1="223.82" y1="-538.48" x2="218.74" y2="-538.48" width="0.1524" layer="91"/>
<label x="218.74" y="-537.97" size="1.778" layer="95"/></segment>
</net>
<net name="LEDP" class="0">
<segment><pinref part="RP1" gate="G$1" pin="2"/>
<wire x1="360.98" y1="-939.80" x2="366.06" y2="-939.80" width="0.1524" layer="91"/>
<label x="366.06" y="-939.29" size="1.778" layer="95"/></segment>
<segment><pinref part="LED3" gate="G$1" pin="A"/>
<wire x1="427.02" y1="-939.80" x2="421.94" y2="-939.80" width="0.1524" layer="91"/>
<label x="421.94" y="-939.29" size="1.778" layer="95"/></segment>
</net>
<net name="LEDRN" class="0">
<segment><pinref part="R4" gate="G$1" pin="2"/>
<wire x1="157.78" y1="-1079.50" x2="162.86" y2="-1079.50" width="0.1524" layer="91"/>
<label x="162.86" y="-1078.99" size="1.778" layer="95"/></segment>
<segment><pinref part="LED4" gate="G$1" pin="A"/>
<wire x1="223.82" y1="-1079.50" x2="218.74" y2="-1079.50" width="0.1524" layer="91"/>
<label x="218.74" y="-1078.99" size="1.778" layer="95"/></segment>
</net>
<net name="LEDHL" class="0">
<segment><pinref part="R5" gate="G$1" pin="2"/>
<wire x1="360.98" y1="-1079.50" x2="366.06" y2="-1079.50" width="0.1524" layer="91"/>
<label x="366.06" y="-1078.99" size="1.778" layer="95"/></segment>
<segment><pinref part="LED5" gate="G$1" pin="A"/>
<wire x1="427.02" y1="-1079.50" x2="421.94" y2="-1079.50" width="0.1524" layer="91"/>
<label x="421.94" y="-1078.99" size="1.778" layer="95"/></segment>
</net>
</nets></sheet></sheets></schematic></drawing></eagle>
