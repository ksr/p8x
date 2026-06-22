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
<package name="FABC96S">
<pad name="A1" x="-2.54" y="39.37" drill="0.9144" diameter="1.524"/>
<pad name="A2" x="-2.54" y="36.83" drill="0.9144" diameter="1.524"/>
<pad name="A3" x="-2.54" y="34.29" drill="0.9144" diameter="1.524"/>
<pad name="A4" x="-2.54" y="31.75" drill="0.9144" diameter="1.524"/>
<pad name="A5" x="-2.54" y="29.21" drill="0.9144" diameter="1.524"/>
<pad name="A6" x="-2.54" y="26.67" drill="0.9144" diameter="1.524"/>
<pad name="A7" x="-2.54" y="24.13" drill="0.9144" diameter="1.524"/>
<pad name="A8" x="-2.54" y="21.59" drill="0.9144" diameter="1.524"/>
<pad name="A9" x="-2.54" y="19.05" drill="0.9144" diameter="1.524"/>
<pad name="A10" x="-2.54" y="16.51" drill="0.9144" diameter="1.524"/>
<pad name="A11" x="-2.54" y="13.97" drill="0.9144" diameter="1.524"/>
<pad name="A12" x="-2.54" y="11.43" drill="0.9144" diameter="1.524"/>
<pad name="A13" x="-2.54" y="8.89" drill="0.9144" diameter="1.524"/>
<pad name="A14" x="-2.54" y="6.35" drill="0.9144" diameter="1.524"/>
<pad name="A15" x="-2.54" y="3.81" drill="0.9144" diameter="1.524"/>
<pad name="A16" x="-2.54" y="1.27" drill="0.9144" diameter="1.524"/>
<pad name="A17" x="-2.54" y="-1.27" drill="0.9144" diameter="1.524"/>
<pad name="A18" x="-2.54" y="-3.81" drill="0.9144" diameter="1.524"/>
<pad name="A19" x="-2.54" y="-6.35" drill="0.9144" diameter="1.524"/>
<pad name="A20" x="-2.54" y="-8.89" drill="0.9144" diameter="1.524"/>
<pad name="A21" x="-2.54" y="-11.43" drill="0.9144" diameter="1.524"/>
<pad name="A22" x="-2.54" y="-13.97" drill="0.9144" diameter="1.524"/>
<pad name="A23" x="-2.54" y="-16.51" drill="0.9144" diameter="1.524"/>
<pad name="A24" x="-2.54" y="-19.05" drill="0.9144" diameter="1.524"/>
<pad name="A25" x="-2.54" y="-21.59" drill="0.9144" diameter="1.524"/>
<pad name="A26" x="-2.54" y="-24.13" drill="0.9144" diameter="1.524"/>
<pad name="A27" x="-2.54" y="-26.67" drill="0.9144" diameter="1.524"/>
<pad name="A28" x="-2.54" y="-29.21" drill="0.9144" diameter="1.524"/>
<pad name="A29" x="-2.54" y="-31.75" drill="0.9144" diameter="1.524"/>
<pad name="A30" x="-2.54" y="-34.29" drill="0.9144" diameter="1.524"/>
<pad name="A31" x="-2.54" y="-36.83" drill="0.9144" diameter="1.524"/>
<pad name="A32" x="-2.54" y="-39.37" drill="0.9144" diameter="1.524"/>
<pad name="B1" x="0.00" y="39.37" drill="0.9144" diameter="1.524"/>
<pad name="B2" x="0.00" y="36.83" drill="0.9144" diameter="1.524"/>
<pad name="B3" x="0.00" y="34.29" drill="0.9144" diameter="1.524"/>
<pad name="B4" x="0.00" y="31.75" drill="0.9144" diameter="1.524"/>
<pad name="B5" x="0.00" y="29.21" drill="0.9144" diameter="1.524"/>
<pad name="B6" x="0.00" y="26.67" drill="0.9144" diameter="1.524"/>
<pad name="B7" x="0.00" y="24.13" drill="0.9144" diameter="1.524"/>
<pad name="B8" x="0.00" y="21.59" drill="0.9144" diameter="1.524"/>
<pad name="B9" x="0.00" y="19.05" drill="0.9144" diameter="1.524"/>
<pad name="B10" x="0.00" y="16.51" drill="0.9144" diameter="1.524"/>
<pad name="B11" x="0.00" y="13.97" drill="0.9144" diameter="1.524"/>
<pad name="B12" x="0.00" y="11.43" drill="0.9144" diameter="1.524"/>
<pad name="B13" x="0.00" y="8.89" drill="0.9144" diameter="1.524"/>
<pad name="B14" x="0.00" y="6.35" drill="0.9144" diameter="1.524"/>
<pad name="B15" x="0.00" y="3.81" drill="0.9144" diameter="1.524"/>
<pad name="B16" x="0.00" y="1.27" drill="0.9144" diameter="1.524"/>
<pad name="B17" x="0.00" y="-1.27" drill="0.9144" diameter="1.524"/>
<pad name="B18" x="0.00" y="-3.81" drill="0.9144" diameter="1.524"/>
<pad name="B19" x="0.00" y="-6.35" drill="0.9144" diameter="1.524"/>
<pad name="B20" x="0.00" y="-8.89" drill="0.9144" diameter="1.524"/>
<pad name="B21" x="0.00" y="-11.43" drill="0.9144" diameter="1.524"/>
<pad name="B22" x="0.00" y="-13.97" drill="0.9144" diameter="1.524"/>
<pad name="B23" x="0.00" y="-16.51" drill="0.9144" diameter="1.524"/>
<pad name="B24" x="0.00" y="-19.05" drill="0.9144" diameter="1.524"/>
<pad name="B25" x="0.00" y="-21.59" drill="0.9144" diameter="1.524"/>
<pad name="B26" x="0.00" y="-24.13" drill="0.9144" diameter="1.524"/>
<pad name="B27" x="0.00" y="-26.67" drill="0.9144" diameter="1.524"/>
<pad name="B28" x="0.00" y="-29.21" drill="0.9144" diameter="1.524"/>
<pad name="B29" x="0.00" y="-31.75" drill="0.9144" diameter="1.524"/>
<pad name="B30" x="0.00" y="-34.29" drill="0.9144" diameter="1.524"/>
<pad name="B31" x="0.00" y="-36.83" drill="0.9144" diameter="1.524"/>
<pad name="B32" x="0.00" y="-39.37" drill="0.9144" diameter="1.524"/>
<pad name="C1" x="2.54" y="39.37" drill="0.9144" diameter="1.524"/>
<pad name="C2" x="2.54" y="36.83" drill="0.9144" diameter="1.524"/>
<pad name="C3" x="2.54" y="34.29" drill="0.9144" diameter="1.524"/>
<pad name="C4" x="2.54" y="31.75" drill="0.9144" diameter="1.524"/>
<pad name="C5" x="2.54" y="29.21" drill="0.9144" diameter="1.524"/>
<pad name="C6" x="2.54" y="26.67" drill="0.9144" diameter="1.524"/>
<pad name="C7" x="2.54" y="24.13" drill="0.9144" diameter="1.524"/>
<pad name="C8" x="2.54" y="21.59" drill="0.9144" diameter="1.524"/>
<pad name="C9" x="2.54" y="19.05" drill="0.9144" diameter="1.524"/>
<pad name="C10" x="2.54" y="16.51" drill="0.9144" diameter="1.524"/>
<pad name="C11" x="2.54" y="13.97" drill="0.9144" diameter="1.524"/>
<pad name="C12" x="2.54" y="11.43" drill="0.9144" diameter="1.524"/>
<pad name="C13" x="2.54" y="8.89" drill="0.9144" diameter="1.524"/>
<pad name="C14" x="2.54" y="6.35" drill="0.9144" diameter="1.524"/>
<pad name="C15" x="2.54" y="3.81" drill="0.9144" diameter="1.524"/>
<pad name="C16" x="2.54" y="1.27" drill="0.9144" diameter="1.524"/>
<pad name="C17" x="2.54" y="-1.27" drill="0.9144" diameter="1.524"/>
<pad name="C18" x="2.54" y="-3.81" drill="0.9144" diameter="1.524"/>
<pad name="C19" x="2.54" y="-6.35" drill="0.9144" diameter="1.524"/>
<pad name="C20" x="2.54" y="-8.89" drill="0.9144" diameter="1.524"/>
<pad name="C21" x="2.54" y="-11.43" drill="0.9144" diameter="1.524"/>
<pad name="C22" x="2.54" y="-13.97" drill="0.9144" diameter="1.524"/>
<pad name="C23" x="2.54" y="-16.51" drill="0.9144" diameter="1.524"/>
<pad name="C24" x="2.54" y="-19.05" drill="0.9144" diameter="1.524"/>
<pad name="C25" x="2.54" y="-21.59" drill="0.9144" diameter="1.524"/>
<pad name="C26" x="2.54" y="-24.13" drill="0.9144" diameter="1.524"/>
<pad name="C27" x="2.54" y="-26.67" drill="0.9144" diameter="1.524"/>
<pad name="C28" x="2.54" y="-29.21" drill="0.9144" diameter="1.524"/>
<pad name="C29" x="2.54" y="-31.75" drill="0.9144" diameter="1.524"/>
<pad name="C30" x="2.54" y="-34.29" drill="0.9144" diameter="1.524"/>
<pad name="C31" x="2.54" y="-36.83" drill="0.9144" diameter="1.524"/>
<pad name="C32" x="2.54" y="-39.37" drill="0.9144" diameter="1.524"/>
<hole x="-0.30" y="45.00" drill="2.794"/>
<hole x="-0.30" y="-45.00" drill="2.794"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="LED5">
<pad name="2" x="0.00" y="0.00" drill="0.9" diameter="1.8"/>
<pad name="1" x="2.54" y="0.00" drill="0.9" diameter="1.8"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="R_AXIAL">
<pad name="1" x="0.00" y="0.00" drill="0.8" diameter="1.6"/>
<pad name="2" x="10.16" y="0.00" drill="0.8" diameter="1.6"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="SIP16">
<pad name="1" x="0.00" y="-2.54" drill="0.8" diameter="1.6"/>
<pad name="2" x="0.00" y="-5.08" drill="0.8" diameter="1.6"/>
<pad name="3" x="0.00" y="-7.62" drill="0.8" diameter="1.6"/>
<pad name="4" x="0.00" y="-10.16" drill="0.8" diameter="1.6"/>
<pad name="5" x="0.00" y="-12.70" drill="0.8" diameter="1.6"/>
<pad name="6" x="0.00" y="-15.24" drill="0.8" diameter="1.6"/>
<pad name="7" x="0.00" y="-17.78" drill="0.8" diameter="1.6"/>
<pad name="8" x="0.00" y="-20.32" drill="0.8" diameter="1.6"/>
<pad name="9" x="0.00" y="-22.86" drill="0.8" diameter="1.6"/>
<pad name="10" x="0.00" y="-25.40" drill="0.8" diameter="1.6"/>
<pad name="11" x="0.00" y="-27.94" drill="0.8" diameter="1.6"/>
<pad name="12" x="0.00" y="-30.48" drill="0.8" diameter="1.6"/>
<pad name="13" x="0.00" y="-33.02" drill="0.8" diameter="1.6"/>
<pad name="14" x="0.00" y="-35.56" drill="0.8" diameter="1.6"/>
<pad name="15" x="0.00" y="-38.10" drill="0.8" diameter="1.6"/>
<pad name="16" x="0.00" y="-40.64" drill="0.8" diameter="1.6"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
</packages>
<symbols>
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
<symbol name="7430">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="12.7" y1="-20.32" x2="-12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-20.32" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-24.13" size="1.778" layer="96">&gt;VALUE</text>
<pin name="A" x="-17.78" y="-0.00" length="middle"/>
<pin name="B" x="-17.78" y="-2.54" length="middle"/>
<pin name="C" x="-17.78" y="-5.08" length="middle"/>
<pin name="D" x="-17.78" y="-7.62" length="middle"/>
<pin name="E" x="-17.78" y="-10.16" length="middle"/>
<pin name="F" x="-17.78" y="-12.70" length="middle"/>
<pin name="G" x="-17.78" y="-15.24" length="middle"/>
<pin name="H" x="-17.78" y="-17.78" length="middle"/>
<pin name="Y" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="VCC" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="GND" x="17.78" y="-5.08" length="middle" rot="R180"/>
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
<symbol name="LEDARR8">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="12.7" y1="-20.32" x2="-12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-20.32" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-24.13" size="1.778" layer="96">&gt;VALUE</text>
<pin name="A1" x="-17.78" y="-0.00" length="middle"/>
<pin name="A2" x="-17.78" y="-2.54" length="middle"/>
<pin name="A3" x="-17.78" y="-5.08" length="middle"/>
<pin name="A4" x="-17.78" y="-7.62" length="middle"/>
<pin name="A5" x="-17.78" y="-10.16" length="middle"/>
<pin name="A6" x="-17.78" y="-12.70" length="middle"/>
<pin name="A7" x="-17.78" y="-15.24" length="middle"/>
<pin name="A8" x="-17.78" y="-17.78" length="middle"/>
<pin name="K1" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="K2" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="K3" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="K4" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="K5" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="K6" x="17.78" y="-12.70" length="middle" rot="R180"/>
<pin name="K7" x="17.78" y="-15.24" length="middle" rot="R180"/>
<pin name="K8" x="17.78" y="-17.78" length="middle" rot="R180"/>
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
<symbol name="RNISO8">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="12.7" y1="-20.32" x2="-12.7" y2="-20.32" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-20.32" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-24.13" size="1.778" layer="96">&gt;VALUE</text>
<pin name="A1" x="-17.78" y="-0.00" length="middle"/>
<pin name="A2" x="-17.78" y="-2.54" length="middle"/>
<pin name="A3" x="-17.78" y="-5.08" length="middle"/>
<pin name="A4" x="-17.78" y="-7.62" length="middle"/>
<pin name="A5" x="-17.78" y="-10.16" length="middle"/>
<pin name="A6" x="-17.78" y="-12.70" length="middle"/>
<pin name="A7" x="-17.78" y="-15.24" length="middle"/>
<pin name="A8" x="-17.78" y="-17.78" length="middle"/>
<pin name="B1" x="17.78" y="-0.00" length="middle" rot="R180"/>
<pin name="B2" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="B3" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="B4" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="B5" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="B6" x="17.78" y="-12.70" length="middle" rot="R180"/>
<pin name="B7" x="17.78" y="-15.24" length="middle" rot="R180"/>
<pin name="B8" x="17.78" y="-17.78" length="middle" rot="R180"/>
</symbol>
</symbols>
<devicesets>
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
<deviceset name="7430" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="7430" x="0" y="0"/></gates>
<devices><device name="" package="DIP14"><connects>
<connect gate="G$1" pin="A" pad="1"/>
<connect gate="G$1" pin="B" pad="2"/>
<connect gate="G$1" pin="C" pad="3"/>
<connect gate="G$1" pin="D" pad="4"/>
<connect gate="G$1" pin="E" pad="5"/>
<connect gate="G$1" pin="F" pad="6"/>
<connect gate="G$1" pin="GND" pad="7"/>
<connect gate="G$1" pin="Y" pad="8"/>
<connect gate="G$1" pin="G" pad="11"/>
<connect gate="G$1" pin="H" pad="12"/>
<connect gate="G$1" pin="VCC" pad="14"/>
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
<deviceset name="CAP" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="CAP" x="0" y="0"/></gates>
<devices><device name="" package="C_DISC"><connects>
<connect gate="G$1" pin="1" pad="1"/>
<connect gate="G$1" pin="2" pad="2"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="DIN96" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="DIN96" x="0" y="0"/></gates>
<devices><device name="" package="FABC96S"><connects>
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
<deviceset name="LEDARR8" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="LEDARR8" x="0" y="0"/></gates>
<devices><device name="" package="DIP16"><connects>
<connect gate="G$1" pin="A1" pad="1"/>
<connect gate="G$1" pin="A2" pad="2"/>
<connect gate="G$1" pin="A3" pad="3"/>
<connect gate="G$1" pin="A4" pad="4"/>
<connect gate="G$1" pin="A5" pad="5"/>
<connect gate="G$1" pin="A6" pad="6"/>
<connect gate="G$1" pin="A7" pad="7"/>
<connect gate="G$1" pin="A8" pad="8"/>
<connect gate="G$1" pin="K1" pad="16"/>
<connect gate="G$1" pin="K2" pad="15"/>
<connect gate="G$1" pin="K3" pad="14"/>
<connect gate="G$1" pin="K4" pad="13"/>
<connect gate="G$1" pin="K5" pad="12"/>
<connect gate="G$1" pin="K6" pad="11"/>
<connect gate="G$1" pin="K7" pad="10"/>
<connect gate="G$1" pin="K8" pad="9"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="RES" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="RES" x="0" y="0"/></gates>
<devices><device name="" package="R_AXIAL"><connects>
<connect gate="G$1" pin="1" pad="1"/>
<connect gate="G$1" pin="2" pad="2"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
<deviceset name="RNISO8" prefix="U" uservalue="yes"><gates><gate name="G$1" symbol="RNISO8" x="0" y="0"/></gates>
<devices><device name="" package="SIP16"><connects>
<connect gate="G$1" pin="A1" pad="1"/>
<connect gate="G$1" pin="A2" pad="3"/>
<connect gate="G$1" pin="A3" pad="5"/>
<connect gate="G$1" pin="A4" pad="7"/>
<connect gate="G$1" pin="A5" pad="9"/>
<connect gate="G$1" pin="A6" pad="11"/>
<connect gate="G$1" pin="A7" pad="13"/>
<connect gate="G$1" pin="A8" pad="15"/>
<connect gate="G$1" pin="B1" pad="2"/>
<connect gate="G$1" pin="B2" pad="4"/>
<connect gate="G$1" pin="B3" pad="6"/>
<connect gate="G$1" pin="B4" pad="8"/>
<connect gate="G$1" pin="B5" pad="10"/>
<connect gate="G$1" pin="B6" pad="12"/>
<connect gate="G$1" pin="B7" pad="14"/>
<connect gate="G$1" pin="B8" pad="16"/>
</connects><technologies><technology name=""/></technologies></device></devices></deviceset>
</devicesets>
</library></libraries>
<classes><class number="0" name="default" width="0" drill="0"/></classes>
<parts>
<part name="J1" library="p8x" deviceset="DIN96" device="" value="MABC96R"/>
<part name="U1" library="p8x" deviceset="7430" device="" value="74HCT30"/>
<part name="U2" library="p8x" deviceset="74138" device="" value="74HCT138"/>
<part name="U3" library="p8x" deviceset="74138" device="" value="74HCT138"/>
<part name="U4" library="p8x" deviceset="GATES14" device="" value="74HCT32"/>
<part name="U5" library="p8x" deviceset="HEX14" device="" value="74HCT14"/>
<part name="U6" library="p8x" deviceset="74374" device="" value="74HCT374"/>
<part name="RL1" library="p8x" deviceset="RNISO8" device="" value="8x330R"/>
<part name="LA1" library="p8x" deviceset="LEDARR8" device="" value="8-LED BAR"/>
<part name="RP1" library="p8x" deviceset="RES" device="" value="1K"/>
<part name="LED3" library="p8x" deviceset="LED" device="" value="GRN"/>
<part name="R4" library="p8x" deviceset="RES" device="" value="1K"/>
<part name="LED4" library="p8x" deviceset="LED" device="" value="YEL"/>
<part name="CD1" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD2" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD3" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD4" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD5" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="CD6" library="p8x" deviceset="CAP" device="" value="100N"/>
</parts><sheets><sheet><plain>
<text x="0" y="40" size="3.81" layer="97">P8X LED OUTPUT CARD (test - write-only 8 LEDs at $FF0C)</text>
<text x="127.30" y="47.64" size="1.778" layer="97">I/O PAGE DEC</text>
<text x="127.30" y="44.64" size="2.032" layer="96">74HCT30</text>
<text x="228.90" y="47.64" size="1.778" layer="97">PORT DEC $FF0C</text>
<text x="228.90" y="44.64" size="2.032" layer="96">74HCT138</text>
<text x="330.50" y="47.64" size="1.778" layer="97">DLD DEC</text>
<text x="330.50" y="44.64" size="2.032" layer="96">74HCT138</text>
<text x="432.10" y="47.64" size="1.778" layer="97">WRITE/CLK GATES</text>
<text x="432.10" y="44.64" size="2.032" layer="96">74HCT32</text>
<text x="127.30" y="-92.06" size="1.778" layer="97">CLKB INVERT</text>
<text x="127.30" y="-95.06" size="2.032" layer="96">74HCT14</text>
<text x="228.90" y="-92.06" size="1.778" layer="97">LED LATCH</text>
<text x="228.90" y="-95.06" size="2.032" layer="96">74HCT374</text>
<text x="330.50" y="-92.06" size="1.778" layer="97">LED Rs</text>
<text x="330.50" y="-95.06" size="2.032" layer="96">8x330R</text>
<text x="432.10" y="-92.06" size="1.778" layer="97">OUTPUT LEDS</text>
<text x="432.10" y="-95.06" size="2.032" layer="96">8-LED BAR</text>
<text x="228.90" y="-231.76" size="1.778" layer="97">POWER</text>
<text x="228.90" y="-234.76" size="2.032" layer="96">GRN</text>
<text x="432.10" y="-231.76" size="1.778" layer="97">WRITE ACT</text>
<text x="432.10" y="-234.76" size="2.032" layer="96">YEL</text>
</plain><instances>
<instance part="J1" gate="G$1" x="0" y="38.1"/>
<instance part="U1" gate="G$1" x="140.0" y="38.1"/>
<instance part="U2" gate="G$1" x="241.6" y="38.1"/>
<instance part="U3" gate="G$1" x="343.2" y="38.1"/>
<instance part="U4" gate="G$1" x="444.79999999999995" y="38.1"/>
<instance part="U5" gate="G$1" x="140.0" y="-101.6"/>
<instance part="U6" gate="G$1" x="241.6" y="-101.6"/>
<instance part="RL1" gate="G$1" x="343.2" y="-101.6"/>
<instance part="LA1" gate="G$1" x="444.79999999999995" y="-101.6"/>
<instance part="RP1" gate="G$1" x="140.0" y="-241.29999999999998"/>
<instance part="LED3" gate="G$1" x="241.6" y="-241.29999999999998"/>
<instance part="R4" gate="G$1" x="343.2" y="-241.29999999999998"/>
<instance part="LED4" gate="G$1" x="444.79999999999995" y="-241.29999999999998"/>
<instance part="CD1" gate="G$1" x="140.0" y="-380.99999999999994"/>
<instance part="CD2" gate="G$1" x="241.6" y="-380.99999999999994"/>
<instance part="CD3" gate="G$1" x="343.2" y="-380.99999999999994"/>
<instance part="CD4" gate="G$1" x="444.79999999999995" y="-380.99999999999994"/>
<instance part="CD5" gate="G$1" x="140.0" y="-520.6999999999999"/>
<instance part="CD6" gate="G$1" x="241.6" y="-520.6999999999999"/>
</instances><busses/><nets>
<net name="A8" class="0">
<segment><pinref part="U1" gate="G$1" pin="A"/>
<wire x1="122.22" y1="38.10" x2="117.14" y2="38.10" width="0.1524" layer="91"/>
<label x="117.14" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C11"/>
<wire x1="17.78" y1="12.70" x2="22.86" y2="12.70" width="0.1524" layer="91"/>
<label x="22.86" y="13.21" size="1.778" layer="95"/></segment>
</net>
<net name="A9" class="0">
<segment><pinref part="U1" gate="G$1" pin="B"/>
<wire x1="122.22" y1="35.56" x2="117.14" y2="35.56" width="0.1524" layer="91"/>
<label x="117.14" y="36.07" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C12"/>
<wire x1="17.78" y1="10.16" x2="22.86" y2="10.16" width="0.1524" layer="91"/>
<label x="22.86" y="10.67" size="1.778" layer="95"/></segment>
</net>
<net name="A10" class="0">
<segment><pinref part="U1" gate="G$1" pin="C"/>
<wire x1="122.22" y1="33.02" x2="117.14" y2="33.02" width="0.1524" layer="91"/>
<label x="117.14" y="33.53" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C13"/>
<wire x1="17.78" y1="7.62" x2="22.86" y2="7.62" width="0.1524" layer="91"/>
<label x="22.86" y="8.13" size="1.778" layer="95"/></segment>
</net>
<net name="A11" class="0">
<segment><pinref part="U1" gate="G$1" pin="D"/>
<wire x1="122.22" y1="30.48" x2="117.14" y2="30.48" width="0.1524" layer="91"/>
<label x="117.14" y="30.99" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C14"/>
<wire x1="17.78" y1="5.08" x2="22.86" y2="5.08" width="0.1524" layer="91"/>
<label x="22.86" y="5.59" size="1.778" layer="95"/></segment>
</net>
<net name="A12" class="0">
<segment><pinref part="U1" gate="G$1" pin="E"/>
<wire x1="122.22" y1="27.94" x2="117.14" y2="27.94" width="0.1524" layer="91"/>
<label x="117.14" y="28.45" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C15"/>
<wire x1="17.78" y1="2.54" x2="22.86" y2="2.54" width="0.1524" layer="91"/>
<label x="22.86" y="3.05" size="1.778" layer="95"/></segment>
</net>
<net name="A13" class="0">
<segment><pinref part="U1" gate="G$1" pin="F"/>
<wire x1="122.22" y1="25.40" x2="117.14" y2="25.40" width="0.1524" layer="91"/>
<label x="117.14" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C16"/>
<wire x1="17.78" y1="0.00" x2="22.86" y2="0.00" width="0.1524" layer="91"/>
<label x="22.86" y="0.51" size="1.778" layer="95"/></segment>
</net>
<net name="A14" class="0">
<segment><pinref part="U1" gate="G$1" pin="G"/>
<wire x1="122.22" y1="22.86" x2="117.14" y2="22.86" width="0.1524" layer="91"/>
<label x="117.14" y="23.37" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C17"/>
<wire x1="17.78" y1="-2.54" x2="22.86" y2="-2.54" width="0.1524" layer="91"/>
<label x="22.86" y="-2.03" size="1.778" layer="95"/></segment>
</net>
<net name="A15" class="0">
<segment><pinref part="U1" gate="G$1" pin="H"/>
<wire x1="122.22" y1="20.32" x2="117.14" y2="20.32" width="0.1524" layer="91"/>
<label x="117.14" y="20.83" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C18"/>
<wire x1="17.78" y1="-5.08" x2="22.86" y2="-5.08" width="0.1524" layer="91"/>
<label x="22.86" y="-4.57" size="1.778" layer="95"/></segment>
</net>
<net name="IOPG" class="0">
<segment><pinref part="U1" gate="G$1" pin="Y"/>
<wire x1="157.78" y1="38.10" x2="162.86" y2="38.10" width="0.1524" layer="91"/>
<label x="162.86" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="U2" gate="G$1" pin="!G2A"/>
<wire x1="223.82" y1="27.94" x2="218.74" y2="27.94" width="0.1524" layer="91"/>
<label x="218.74" y="28.45" size="1.778" layer="95"/></segment>
</net>
<net name="A1" class="0">
<segment><pinref part="U2" gate="G$1" pin="A"/>
<wire x1="223.82" y1="38.10" x2="218.74" y2="38.10" width="0.1524" layer="91"/>
<label x="218.74" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C4"/>
<wire x1="17.78" y1="30.48" x2="22.86" y2="30.48" width="0.1524" layer="91"/>
<label x="22.86" y="30.99" size="1.778" layer="95"/></segment>
</net>
<net name="A2" class="0">
<segment><pinref part="U2" gate="G$1" pin="B"/>
<wire x1="223.82" y1="35.56" x2="218.74" y2="35.56" width="0.1524" layer="91"/>
<label x="218.74" y="36.07" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C5"/>
<wire x1="17.78" y1="27.94" x2="22.86" y2="27.94" width="0.1524" layer="91"/>
<label x="22.86" y="28.45" size="1.778" layer="95"/></segment>
</net>
<net name="A3" class="0">
<segment><pinref part="U2" gate="G$1" pin="C"/>
<wire x1="223.82" y1="33.02" x2="218.74" y2="33.02" width="0.1524" layer="91"/>
<label x="218.74" y="33.53" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C6"/>
<wire x1="17.78" y1="25.40" x2="22.86" y2="25.40" width="0.1524" layer="91"/>
<label x="22.86" y="25.91" size="1.778" layer="95"/></segment>
</net>
<net name="VCC" class="0">
<segment><pinref part="U2" gate="G$1" pin="G1"/>
<wire x1="223.82" y1="30.48" x2="218.74" y2="30.48" width="0.1524" layer="91"/>
<label x="218.74" y="30.99" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="G1"/>
<wire x1="325.42" y1="30.48" x2="320.34" y2="30.48" width="0.1524" layer="91"/>
<label x="320.34" y="30.99" size="1.778" layer="95"/></segment>
<segment><pinref part="RP1" gate="G$1" pin="1"/>
<wire x1="122.22" y1="-241.30" x2="117.14" y2="-241.30" width="0.1524" layer="91"/>
<label x="117.14" y="-240.79" size="1.778" layer="95"/></segment>
<segment><pinref part="R4" gate="G$1" pin="1"/>
<wire x1="325.42" y1="-241.30" x2="320.34" y2="-241.30" width="0.1524" layer="91"/>
<label x="320.34" y="-240.79" size="1.778" layer="95"/></segment>
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
<wire x1="122.22" y1="-381.00" x2="117.14" y2="-381.00" width="0.1524" layer="91"/>
<label x="117.14" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD2" gate="G$1" pin="1"/>
<wire x1="223.82" y1="-381.00" x2="218.74" y2="-381.00" width="0.1524" layer="91"/>
<label x="218.74" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD3" gate="G$1" pin="1"/>
<wire x1="325.42" y1="-381.00" x2="320.34" y2="-381.00" width="0.1524" layer="91"/>
<label x="320.34" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD4" gate="G$1" pin="1"/>
<wire x1="427.02" y1="-381.00" x2="421.94" y2="-381.00" width="0.1524" layer="91"/>
<label x="421.94" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD5" gate="G$1" pin="1"/>
<wire x1="122.22" y1="-520.70" x2="117.14" y2="-520.70" width="0.1524" layer="91"/>
<label x="117.14" y="-520.19" size="1.778" layer="95"/></segment>
<segment><pinref part="CD6" gate="G$1" pin="1"/>
<wire x1="223.82" y1="-520.70" x2="218.74" y2="-520.70" width="0.1524" layer="91"/>
<label x="218.74" y="-520.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U1" gate="G$1" pin="VCC"/>
<wire x1="157.78" y1="35.56" x2="162.86" y2="35.56" width="0.1524" layer="91"/>
<label x="162.86" y="36.07" size="1.778" layer="95"/></segment>
<segment><pinref part="U2" gate="G$1" pin="VCC"/>
<wire x1="259.38" y1="17.78" x2="264.46" y2="17.78" width="0.1524" layer="91"/>
<label x="264.46" y="18.29" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="VCC"/>
<wire x1="360.98" y1="17.78" x2="366.06" y2="17.78" width="0.1524" layer="91"/>
<label x="366.06" y="18.29" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="VCC"/>
<wire x1="462.58" y1="27.94" x2="467.66" y2="27.94" width="0.1524" layer="91"/>
<label x="467.66" y="28.45" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="VCC"/>
<wire x1="157.78" y1="-116.84" x2="162.86" y2="-116.84" width="0.1524" layer="91"/>
<label x="162.86" y="-116.33" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="VCC"/>
<wire x1="259.38" y1="-121.92" x2="264.46" y2="-121.92" width="0.1524" layer="91"/>
<label x="264.46" y="-121.41" size="1.778" layer="95"/></segment>
</net>
<net name="A4" class="0">
<segment><pinref part="U2" gate="G$1" pin="!G2B"/>
<wire x1="223.82" y1="25.40" x2="218.74" y2="25.40" width="0.1524" layer="91"/>
<label x="218.74" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="C7"/>
<wire x1="17.78" y1="22.86" x2="22.86" y2="22.86" width="0.1524" layer="91"/>
<label x="22.86" y="23.37" size="1.778" layer="95"/></segment>
</net>
<net name="-SEL" class="0">
<segment><pinref part="U2" gate="G$1" pin="Y6"/>
<wire x1="259.38" y1="22.86" x2="264.46" y2="22.86" width="0.1524" layer="91"/>
<label x="264.46" y="23.37" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="1A"/>
<wire x1="427.02" y1="38.10" x2="421.94" y2="38.10" width="0.1524" layer="91"/>
<label x="421.94" y="38.61" size="1.778" layer="95"/></segment>
</net>
<net name="DLD0" class="0">
<segment><pinref part="U3" gate="G$1" pin="A"/>
<wire x1="325.42" y1="38.10" x2="320.34" y2="38.10" width="0.1524" layer="91"/>
<label x="320.34" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A16"/>
<wire x1="-17.78" y1="0.00" x2="-22.86" y2="0.00" width="0.1524" layer="91"/>
<label x="-22.86" y="0.51" size="1.778" layer="95"/></segment>
</net>
<net name="DLD1" class="0">
<segment><pinref part="U3" gate="G$1" pin="B"/>
<wire x1="325.42" y1="35.56" x2="320.34" y2="35.56" width="0.1524" layer="91"/>
<label x="320.34" y="36.07" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A17"/>
<wire x1="-17.78" y1="-2.54" x2="-22.86" y2="-2.54" width="0.1524" layer="91"/>
<label x="-22.86" y="-2.03" size="1.778" layer="95"/></segment>
</net>
<net name="DLD2" class="0">
<segment><pinref part="U3" gate="G$1" pin="C"/>
<wire x1="325.42" y1="33.02" x2="320.34" y2="33.02" width="0.1524" layer="91"/>
<label x="320.34" y="33.53" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A18"/>
<wire x1="-17.78" y1="-5.08" x2="-22.86" y2="-5.08" width="0.1524" layer="91"/>
<label x="-22.86" y="-4.57" size="1.778" layer="95"/></segment>
</net>
<net name="DLD3" class="0">
<segment><pinref part="U3" gate="G$1" pin="!G2A"/>
<wire x1="325.42" y1="27.94" x2="320.34" y2="27.94" width="0.1524" layer="91"/>
<label x="320.34" y="28.45" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A19"/>
<wire x1="-17.78" y1="-7.62" x2="-22.86" y2="-7.62" width="0.1524" layer="91"/>
<label x="-22.86" y="-7.11" size="1.778" layer="95"/></segment>
</net>
<net name="GND" class="0">
<segment><pinref part="U3" gate="G$1" pin="!G2B"/>
<wire x1="325.42" y1="25.40" x2="320.34" y2="25.40" width="0.1524" layer="91"/>
<label x="320.34" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="!OC"/>
<wire x1="223.82" y1="-101.60" x2="218.74" y2="-101.60" width="0.1524" layer="91"/>
<label x="218.74" y="-101.09" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="K1"/>
<wire x1="462.58" y1="-101.60" x2="467.66" y2="-101.60" width="0.1524" layer="91"/>
<label x="467.66" y="-101.09" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="K2"/>
<wire x1="462.58" y1="-104.14" x2="467.66" y2="-104.14" width="0.1524" layer="91"/>
<label x="467.66" y="-103.63" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="K3"/>
<wire x1="462.58" y1="-106.68" x2="467.66" y2="-106.68" width="0.1524" layer="91"/>
<label x="467.66" y="-106.17" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="K4"/>
<wire x1="462.58" y1="-109.22" x2="467.66" y2="-109.22" width="0.1524" layer="91"/>
<label x="467.66" y="-108.71" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="K5"/>
<wire x1="462.58" y1="-111.76" x2="467.66" y2="-111.76" width="0.1524" layer="91"/>
<label x="467.66" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="K6"/>
<wire x1="462.58" y1="-114.30" x2="467.66" y2="-114.30" width="0.1524" layer="91"/>
<label x="467.66" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="K7"/>
<wire x1="462.58" y1="-116.84" x2="467.66" y2="-116.84" width="0.1524" layer="91"/>
<label x="467.66" y="-116.33" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="K8"/>
<wire x1="462.58" y1="-119.38" x2="467.66" y2="-119.38" width="0.1524" layer="91"/>
<label x="467.66" y="-118.87" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="3A"/>
<wire x1="427.02" y1="27.94" x2="421.94" y2="27.94" width="0.1524" layer="91"/>
<label x="421.94" y="28.45" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="3B"/>
<wire x1="427.02" y1="25.40" x2="421.94" y2="25.40" width="0.1524" layer="91"/>
<label x="421.94" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="4A"/>
<wire x1="427.02" y1="22.86" x2="421.94" y2="22.86" width="0.1524" layer="91"/>
<label x="421.94" y="23.37" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="4B"/>
<wire x1="427.02" y1="20.32" x2="421.94" y2="20.32" width="0.1524" layer="91"/>
<label x="421.94" y="20.83" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="2A"/>
<wire x1="122.22" y1="-104.14" x2="117.14" y2="-104.14" width="0.1524" layer="91"/>
<label x="117.14" y="-103.63" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="3A"/>
<wire x1="122.22" y1="-106.68" x2="117.14" y2="-106.68" width="0.1524" layer="91"/>
<label x="117.14" y="-106.17" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="4A"/>
<wire x1="122.22" y1="-109.22" x2="117.14" y2="-109.22" width="0.1524" layer="91"/>
<label x="117.14" y="-108.71" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="5A"/>
<wire x1="122.22" y1="-111.76" x2="117.14" y2="-111.76" width="0.1524" layer="91"/>
<label x="117.14" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="6A"/>
<wire x1="122.22" y1="-114.30" x2="117.14" y2="-114.30" width="0.1524" layer="91"/>
<label x="117.14" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="LED3" gate="G$1" pin="K"/>
<wire x1="259.38" y1="-241.30" x2="264.46" y2="-241.30" width="0.1524" layer="91"/>
<label x="264.46" y="-240.79" size="1.778" layer="95"/></segment>
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
<wire x1="157.78" y1="-381.00" x2="162.86" y2="-381.00" width="0.1524" layer="91"/>
<label x="162.86" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD2" gate="G$1" pin="2"/>
<wire x1="259.38" y1="-381.00" x2="264.46" y2="-381.00" width="0.1524" layer="91"/>
<label x="264.46" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD3" gate="G$1" pin="2"/>
<wire x1="360.98" y1="-381.00" x2="366.06" y2="-381.00" width="0.1524" layer="91"/>
<label x="366.06" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD4" gate="G$1" pin="2"/>
<wire x1="462.58" y1="-381.00" x2="467.66" y2="-381.00" width="0.1524" layer="91"/>
<label x="467.66" y="-380.49" size="1.778" layer="95"/></segment>
<segment><pinref part="CD5" gate="G$1" pin="2"/>
<wire x1="157.78" y1="-520.70" x2="162.86" y2="-520.70" width="0.1524" layer="91"/>
<label x="162.86" y="-520.19" size="1.778" layer="95"/></segment>
<segment><pinref part="CD6" gate="G$1" pin="2"/>
<wire x1="259.38" y1="-520.70" x2="264.46" y2="-520.70" width="0.1524" layer="91"/>
<label x="264.46" y="-520.19" size="1.778" layer="95"/></segment>
<segment><pinref part="U1" gate="G$1" pin="GND"/>
<wire x1="157.78" y1="33.02" x2="162.86" y2="33.02" width="0.1524" layer="91"/>
<label x="162.86" y="33.53" size="1.778" layer="95"/></segment>
<segment><pinref part="U2" gate="G$1" pin="GND"/>
<wire x1="259.38" y1="15.24" x2="264.46" y2="15.24" width="0.1524" layer="91"/>
<label x="264.46" y="15.75" size="1.778" layer="95"/></segment>
<segment><pinref part="U3" gate="G$1" pin="GND"/>
<wire x1="360.98" y1="15.24" x2="366.06" y2="15.24" width="0.1524" layer="91"/>
<label x="366.06" y="15.75" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="GND"/>
<wire x1="462.58" y1="25.40" x2="467.66" y2="25.40" width="0.1524" layer="91"/>
<label x="467.66" y="25.91" size="1.778" layer="95"/></segment>
<segment><pinref part="U5" gate="G$1" pin="GND"/>
<wire x1="157.78" y1="-119.38" x2="162.86" y2="-119.38" width="0.1524" layer="91"/>
<label x="162.86" y="-118.87" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="GND"/>
<wire x1="259.38" y1="-124.46" x2="264.46" y2="-124.46" width="0.1524" layer="91"/>
<label x="264.46" y="-123.95" size="1.778" layer="95"/></segment>
</net>
<net name="-MEMW" class="0">
<segment><pinref part="U3" gate="G$1" pin="Y7"/>
<wire x1="360.98" y1="20.32" x2="366.06" y2="20.32" width="0.1524" layer="91"/>
<label x="366.06" y="20.83" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="1B"/>
<wire x1="427.02" y1="35.56" x2="421.94" y2="35.56" width="0.1524" layer="91"/>
<label x="421.94" y="36.07" size="1.778" layer="95"/></segment>
</net>
<net name="WRSEL" class="0">
<segment><pinref part="U4" gate="G$1" pin="1Y"/>
<wire x1="462.58" y1="38.10" x2="467.66" y2="38.10" width="0.1524" layer="91"/>
<label x="467.66" y="38.61" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="2A"/>
<wire x1="427.02" y1="33.02" x2="421.94" y2="33.02" width="0.1524" layer="91"/>
<label x="421.94" y="33.53" size="1.778" layer="95"/></segment>
<segment><pinref part="LED4" gate="G$1" pin="K"/>
<wire x1="462.58" y1="-241.30" x2="467.66" y2="-241.30" width="0.1524" layer="91"/>
<label x="467.66" y="-240.79" size="1.778" layer="95"/></segment>
</net>
<net name="CLKB" class="0">
<segment><pinref part="U5" gate="G$1" pin="1A"/>
<wire x1="122.22" y1="-101.60" x2="117.14" y2="-101.60" width="0.1524" layer="91"/>
<label x="117.14" y="-101.09" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A25"/>
<wire x1="-17.78" y1="-22.86" x2="-22.86" y2="-22.86" width="0.1524" layer="91"/>
<label x="-22.86" y="-22.35" size="1.778" layer="95"/></segment>
</net>
<net name="CLKBN" class="0">
<segment><pinref part="U5" gate="G$1" pin="1Y"/>
<wire x1="157.78" y1="-101.60" x2="162.86" y2="-101.60" width="0.1524" layer="91"/>
<label x="162.86" y="-101.09" size="1.778" layer="95"/></segment>
<segment><pinref part="U4" gate="G$1" pin="2B"/>
<wire x1="427.02" y1="30.48" x2="421.94" y2="30.48" width="0.1524" layer="91"/>
<label x="421.94" y="30.99" size="1.778" layer="95"/></segment>
</net>
<net name="LCK" class="0">
<segment><pinref part="U4" gate="G$1" pin="2Y"/>
<wire x1="462.58" y1="35.56" x2="467.66" y2="35.56" width="0.1524" layer="91"/>
<label x="467.66" y="36.07" size="1.778" layer="95"/></segment>
<segment><pinref part="U6" gate="G$1" pin="CLK"/>
<wire x1="223.82" y1="-104.14" x2="218.74" y2="-104.14" width="0.1524" layer="91"/>
<label x="218.74" y="-103.63" size="1.778" layer="95"/></segment>
</net>
<net name="D0" class="0">
<segment><pinref part="U6" gate="G$1" pin="D1"/>
<wire x1="223.82" y1="-106.68" x2="218.74" y2="-106.68" width="0.1524" layer="91"/>
<label x="218.74" y="-106.17" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A3"/>
<wire x1="-17.78" y1="33.02" x2="-22.86" y2="33.02" width="0.1524" layer="91"/>
<label x="-22.86" y="33.53" size="1.778" layer="95"/></segment>
</net>
<net name="LP0" class="0">
<segment><pinref part="U6" gate="G$1" pin="Q1"/>
<wire x1="259.38" y1="-101.60" x2="264.46" y2="-101.60" width="0.1524" layer="91"/>
<label x="264.46" y="-101.09" size="1.778" layer="95"/></segment>
<segment><pinref part="RL1" gate="G$1" pin="A1"/>
<wire x1="325.42" y1="-101.60" x2="320.34" y2="-101.60" width="0.1524" layer="91"/>
<label x="320.34" y="-101.09" size="1.778" layer="95"/></segment>
</net>
<net name="LR0" class="0">
<segment><pinref part="RL1" gate="G$1" pin="B1"/>
<wire x1="360.98" y1="-101.60" x2="366.06" y2="-101.60" width="0.1524" layer="91"/>
<label x="366.06" y="-101.09" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="A1"/>
<wire x1="427.02" y1="-101.60" x2="421.94" y2="-101.60" width="0.1524" layer="91"/>
<label x="421.94" y="-101.09" size="1.778" layer="95"/></segment>
</net>
<net name="D1" class="0">
<segment><pinref part="U6" gate="G$1" pin="D2"/>
<wire x1="223.82" y1="-109.22" x2="218.74" y2="-109.22" width="0.1524" layer="91"/>
<label x="218.74" y="-108.71" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A4"/>
<wire x1="-17.78" y1="30.48" x2="-22.86" y2="30.48" width="0.1524" layer="91"/>
<label x="-22.86" y="30.99" size="1.778" layer="95"/></segment>
</net>
<net name="LP1" class="0">
<segment><pinref part="U6" gate="G$1" pin="Q2"/>
<wire x1="259.38" y1="-104.14" x2="264.46" y2="-104.14" width="0.1524" layer="91"/>
<label x="264.46" y="-103.63" size="1.778" layer="95"/></segment>
<segment><pinref part="RL1" gate="G$1" pin="A2"/>
<wire x1="325.42" y1="-104.14" x2="320.34" y2="-104.14" width="0.1524" layer="91"/>
<label x="320.34" y="-103.63" size="1.778" layer="95"/></segment>
</net>
<net name="LR1" class="0">
<segment><pinref part="RL1" gate="G$1" pin="B2"/>
<wire x1="360.98" y1="-104.14" x2="366.06" y2="-104.14" width="0.1524" layer="91"/>
<label x="366.06" y="-103.63" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="A2"/>
<wire x1="427.02" y1="-104.14" x2="421.94" y2="-104.14" width="0.1524" layer="91"/>
<label x="421.94" y="-103.63" size="1.778" layer="95"/></segment>
</net>
<net name="D2" class="0">
<segment><pinref part="U6" gate="G$1" pin="D3"/>
<wire x1="223.82" y1="-111.76" x2="218.74" y2="-111.76" width="0.1524" layer="91"/>
<label x="218.74" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A5"/>
<wire x1="-17.78" y1="27.94" x2="-22.86" y2="27.94" width="0.1524" layer="91"/>
<label x="-22.86" y="28.45" size="1.778" layer="95"/></segment>
</net>
<net name="LP2" class="0">
<segment><pinref part="U6" gate="G$1" pin="Q3"/>
<wire x1="259.38" y1="-106.68" x2="264.46" y2="-106.68" width="0.1524" layer="91"/>
<label x="264.46" y="-106.17" size="1.778" layer="95"/></segment>
<segment><pinref part="RL1" gate="G$1" pin="A3"/>
<wire x1="325.42" y1="-106.68" x2="320.34" y2="-106.68" width="0.1524" layer="91"/>
<label x="320.34" y="-106.17" size="1.778" layer="95"/></segment>
</net>
<net name="LR2" class="0">
<segment><pinref part="RL1" gate="G$1" pin="B3"/>
<wire x1="360.98" y1="-106.68" x2="366.06" y2="-106.68" width="0.1524" layer="91"/>
<label x="366.06" y="-106.17" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="A3"/>
<wire x1="427.02" y1="-106.68" x2="421.94" y2="-106.68" width="0.1524" layer="91"/>
<label x="421.94" y="-106.17" size="1.778" layer="95"/></segment>
</net>
<net name="D3" class="0">
<segment><pinref part="U6" gate="G$1" pin="D4"/>
<wire x1="223.82" y1="-114.30" x2="218.74" y2="-114.30" width="0.1524" layer="91"/>
<label x="218.74" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A6"/>
<wire x1="-17.78" y1="25.40" x2="-22.86" y2="25.40" width="0.1524" layer="91"/>
<label x="-22.86" y="25.91" size="1.778" layer="95"/></segment>
</net>
<net name="LP3" class="0">
<segment><pinref part="U6" gate="G$1" pin="Q4"/>
<wire x1="259.38" y1="-109.22" x2="264.46" y2="-109.22" width="0.1524" layer="91"/>
<label x="264.46" y="-108.71" size="1.778" layer="95"/></segment>
<segment><pinref part="RL1" gate="G$1" pin="A4"/>
<wire x1="325.42" y1="-109.22" x2="320.34" y2="-109.22" width="0.1524" layer="91"/>
<label x="320.34" y="-108.71" size="1.778" layer="95"/></segment>
</net>
<net name="LR3" class="0">
<segment><pinref part="RL1" gate="G$1" pin="B4"/>
<wire x1="360.98" y1="-109.22" x2="366.06" y2="-109.22" width="0.1524" layer="91"/>
<label x="366.06" y="-108.71" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="A4"/>
<wire x1="427.02" y1="-109.22" x2="421.94" y2="-109.22" width="0.1524" layer="91"/>
<label x="421.94" y="-108.71" size="1.778" layer="95"/></segment>
</net>
<net name="D4" class="0">
<segment><pinref part="U6" gate="G$1" pin="D5"/>
<wire x1="223.82" y1="-116.84" x2="218.74" y2="-116.84" width="0.1524" layer="91"/>
<label x="218.74" y="-116.33" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A7"/>
<wire x1="-17.78" y1="22.86" x2="-22.86" y2="22.86" width="0.1524" layer="91"/>
<label x="-22.86" y="23.37" size="1.778" layer="95"/></segment>
</net>
<net name="LP4" class="0">
<segment><pinref part="U6" gate="G$1" pin="Q5"/>
<wire x1="259.38" y1="-111.76" x2="264.46" y2="-111.76" width="0.1524" layer="91"/>
<label x="264.46" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="RL1" gate="G$1" pin="A5"/>
<wire x1="325.42" y1="-111.76" x2="320.34" y2="-111.76" width="0.1524" layer="91"/>
<label x="320.34" y="-111.25" size="1.778" layer="95"/></segment>
</net>
<net name="LR4" class="0">
<segment><pinref part="RL1" gate="G$1" pin="B5"/>
<wire x1="360.98" y1="-111.76" x2="366.06" y2="-111.76" width="0.1524" layer="91"/>
<label x="366.06" y="-111.25" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="A5"/>
<wire x1="427.02" y1="-111.76" x2="421.94" y2="-111.76" width="0.1524" layer="91"/>
<label x="421.94" y="-111.25" size="1.778" layer="95"/></segment>
</net>
<net name="D5" class="0">
<segment><pinref part="U6" gate="G$1" pin="D6"/>
<wire x1="223.82" y1="-119.38" x2="218.74" y2="-119.38" width="0.1524" layer="91"/>
<label x="218.74" y="-118.87" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A8"/>
<wire x1="-17.78" y1="20.32" x2="-22.86" y2="20.32" width="0.1524" layer="91"/>
<label x="-22.86" y="20.83" size="1.778" layer="95"/></segment>
</net>
<net name="LP5" class="0">
<segment><pinref part="U6" gate="G$1" pin="Q6"/>
<wire x1="259.38" y1="-114.30" x2="264.46" y2="-114.30" width="0.1524" layer="91"/>
<label x="264.46" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="RL1" gate="G$1" pin="A6"/>
<wire x1="325.42" y1="-114.30" x2="320.34" y2="-114.30" width="0.1524" layer="91"/>
<label x="320.34" y="-113.79" size="1.778" layer="95"/></segment>
</net>
<net name="LR5" class="0">
<segment><pinref part="RL1" gate="G$1" pin="B6"/>
<wire x1="360.98" y1="-114.30" x2="366.06" y2="-114.30" width="0.1524" layer="91"/>
<label x="366.06" y="-113.79" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="A6"/>
<wire x1="427.02" y1="-114.30" x2="421.94" y2="-114.30" width="0.1524" layer="91"/>
<label x="421.94" y="-113.79" size="1.778" layer="95"/></segment>
</net>
<net name="D6" class="0">
<segment><pinref part="U6" gate="G$1" pin="D7"/>
<wire x1="223.82" y1="-121.92" x2="218.74" y2="-121.92" width="0.1524" layer="91"/>
<label x="218.74" y="-121.41" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A9"/>
<wire x1="-17.78" y1="17.78" x2="-22.86" y2="17.78" width="0.1524" layer="91"/>
<label x="-22.86" y="18.29" size="1.778" layer="95"/></segment>
</net>
<net name="LP6" class="0">
<segment><pinref part="U6" gate="G$1" pin="Q7"/>
<wire x1="259.38" y1="-116.84" x2="264.46" y2="-116.84" width="0.1524" layer="91"/>
<label x="264.46" y="-116.33" size="1.778" layer="95"/></segment>
<segment><pinref part="RL1" gate="G$1" pin="A7"/>
<wire x1="325.42" y1="-116.84" x2="320.34" y2="-116.84" width="0.1524" layer="91"/>
<label x="320.34" y="-116.33" size="1.778" layer="95"/></segment>
</net>
<net name="LR6" class="0">
<segment><pinref part="RL1" gate="G$1" pin="B7"/>
<wire x1="360.98" y1="-116.84" x2="366.06" y2="-116.84" width="0.1524" layer="91"/>
<label x="366.06" y="-116.33" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="A7"/>
<wire x1="427.02" y1="-116.84" x2="421.94" y2="-116.84" width="0.1524" layer="91"/>
<label x="421.94" y="-116.33" size="1.778" layer="95"/></segment>
</net>
<net name="D7" class="0">
<segment><pinref part="U6" gate="G$1" pin="D8"/>
<wire x1="223.82" y1="-124.46" x2="218.74" y2="-124.46" width="0.1524" layer="91"/>
<label x="218.74" y="-123.95" size="1.778" layer="95"/></segment>
<segment><pinref part="J1" gate="G$1" pin="A10"/>
<wire x1="-17.78" y1="15.24" x2="-22.86" y2="15.24" width="0.1524" layer="91"/>
<label x="-22.86" y="15.75" size="1.778" layer="95"/></segment>
</net>
<net name="LP7" class="0">
<segment><pinref part="U6" gate="G$1" pin="Q8"/>
<wire x1="259.38" y1="-119.38" x2="264.46" y2="-119.38" width="0.1524" layer="91"/>
<label x="264.46" y="-118.87" size="1.778" layer="95"/></segment>
<segment><pinref part="RL1" gate="G$1" pin="A8"/>
<wire x1="325.42" y1="-119.38" x2="320.34" y2="-119.38" width="0.1524" layer="91"/>
<label x="320.34" y="-118.87" size="1.778" layer="95"/></segment>
</net>
<net name="LR7" class="0">
<segment><pinref part="RL1" gate="G$1" pin="B8"/>
<wire x1="360.98" y1="-119.38" x2="366.06" y2="-119.38" width="0.1524" layer="91"/>
<label x="366.06" y="-118.87" size="1.778" layer="95"/></segment>
<segment><pinref part="LA1" gate="G$1" pin="A8"/>
<wire x1="427.02" y1="-119.38" x2="421.94" y2="-119.38" width="0.1524" layer="91"/>
<label x="421.94" y="-118.87" size="1.778" layer="95"/></segment>
</net>
<net name="LEDP" class="0">
<segment><pinref part="RP1" gate="G$1" pin="2"/>
<wire x1="157.78" y1="-241.30" x2="162.86" y2="-241.30" width="0.1524" layer="91"/>
<label x="162.86" y="-240.79" size="1.778" layer="95"/></segment>
<segment><pinref part="LED3" gate="G$1" pin="A"/>
<wire x1="223.82" y1="-241.30" x2="218.74" y2="-241.30" width="0.1524" layer="91"/>
<label x="218.74" y="-240.79" size="1.778" layer="95"/></segment>
</net>
<net name="LEDWR" class="0">
<segment><pinref part="R4" gate="G$1" pin="2"/>
<wire x1="360.98" y1="-241.30" x2="366.06" y2="-241.30" width="0.1524" layer="91"/>
<label x="366.06" y="-240.79" size="1.778" layer="95"/></segment>
<segment><pinref part="LED4" gate="G$1" pin="A"/>
<wire x1="427.02" y1="-241.30" x2="421.94" y2="-241.30" width="0.1524" layer="91"/>
<label x="421.94" y="-240.79" size="1.778" layer="95"/></segment>
</net>
</nets></sheet></sheets></schematic></drawing></eagle>
