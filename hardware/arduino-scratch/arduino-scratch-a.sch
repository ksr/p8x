<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE eagle SYSTEM "eagle.dtd">
<eagle version="9.7.0">
<drawing>
<settings>
<setting alwaysvectorfont="no"/>
<setting verticaltext="up"/>
</settings>
<grid distance="0.1" unitdist="inch" unit="inch" style="lines" multiple="1" display="no" altdistance="0.01" altunitdist="inch" altunit="inch"/>
<layers>
<layer number="1" name="Top" color="4" fill="1" visible="no" active="no"/>
<layer number="2" name="Route2" color="16" fill="1" visible="no" active="no"/>
<layer number="3" name="Route3" color="17" fill="1" visible="no" active="no"/>
<layer number="4" name="Route4" color="18" fill="1" visible="no" active="no"/>
<layer number="5" name="Route5" color="19" fill="1" visible="no" active="no"/>
<layer number="6" name="Route6" color="25" fill="1" visible="no" active="no"/>
<layer number="7" name="Route7" color="26" fill="1" visible="no" active="no"/>
<layer number="8" name="Route8" color="27" fill="1" visible="no" active="no"/>
<layer number="9" name="Route9" color="28" fill="1" visible="no" active="no"/>
<layer number="10" name="Route10" color="29" fill="1" visible="no" active="no"/>
<layer number="11" name="Route11" color="30" fill="1" visible="no" active="no"/>
<layer number="12" name="Route12" color="20" fill="1" visible="no" active="no"/>
<layer number="13" name="Route13" color="21" fill="1" visible="no" active="no"/>
<layer number="14" name="Route14" color="22" fill="1" visible="no" active="no"/>
<layer number="15" name="Route15" color="23" fill="1" visible="no" active="no"/>
<layer number="16" name="Bottom" color="1" fill="1" visible="no" active="no"/>
<layer number="17" name="Pads" color="2" fill="1" visible="no" active="no"/>
<layer number="18" name="Vias" color="2" fill="1" visible="no" active="no"/>
<layer number="19" name="Unrouted" color="6" fill="1" visible="no" active="no"/>
<layer number="20" name="Dimension" color="24" fill="1" visible="no" active="no"/>
<layer number="21" name="tPlace" color="7" fill="1" visible="no" active="no"/>
<layer number="22" name="bPlace" color="7" fill="1" visible="no" active="no"/>
<layer number="23" name="tOrigins" color="15" fill="1" visible="no" active="no"/>
<layer number="24" name="bOrigins" color="15" fill="1" visible="no" active="no"/>
<layer number="25" name="tNames" color="7" fill="1" visible="no" active="no"/>
<layer number="26" name="bNames" color="7" fill="1" visible="no" active="no"/>
<layer number="27" name="tValues" color="7" fill="1" visible="no" active="no"/>
<layer number="28" name="bValues" color="7" fill="1" visible="no" active="no"/>
<layer number="29" name="tStop" color="7" fill="3" visible="no" active="no"/>
<layer number="30" name="bStop" color="7" fill="6" visible="no" active="no"/>
<layer number="31" name="tCream" color="7" fill="4" visible="no" active="no"/>
<layer number="32" name="bCream" color="7" fill="5" visible="no" active="no"/>
<layer number="33" name="tFinish" color="6" fill="3" visible="no" active="no"/>
<layer number="34" name="bFinish" color="6" fill="6" visible="no" active="no"/>
<layer number="35" name="tGlue" color="7" fill="4" visible="no" active="no"/>
<layer number="36" name="bGlue" color="7" fill="5" visible="no" active="no"/>
<layer number="37" name="tTest" color="7" fill="1" visible="no" active="no"/>
<layer number="38" name="bTest" color="7" fill="1" visible="no" active="no"/>
<layer number="39" name="tKeepout" color="4" fill="11" visible="no" active="no"/>
<layer number="40" name="bKeepout" color="1" fill="11" visible="no" active="no"/>
<layer number="41" name="tRestrict" color="4" fill="8" visible="no" active="no"/>
<layer number="42" name="bRestrict" color="1" fill="10" visible="no" active="no"/>
<layer number="43" name="vRestrict" color="2" fill="10" visible="no" active="no"/>
<layer number="44" name="Drills" color="7" fill="1" visible="no" active="no"/>
<layer number="45" name="Holes" color="7" fill="1" visible="no" active="no"/>
<layer number="46" name="Milling" color="3" fill="1" visible="no" active="no"/>
<layer number="47" name="Measures" color="7" fill="1" visible="no" active="no"/>
<layer number="48" name="Document" color="7" fill="1" visible="no" active="no"/>
<layer number="49" name="Reference" color="7" fill="1" visible="no" active="no"/>
<layer number="51" name="tDocu" color="7" fill="1" visible="no" active="no"/>
<layer number="52" name="bDocu" color="7" fill="1" visible="no" active="no"/>
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
<libraries>
<library name="p8x">
<packages>
<package name="CP_RADIAL">
<pad name="1" x="0" y="0" drill="0.9" diameter="1.8"/>
<pad name="2" x="0" y="-5.08" drill="0.9" diameter="1.8"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
<wire x1="1.9" y1="0" x2="3.3" y2="0" width="0.3048" layer="21"/>
<wire x1="2.6" y1="-0.7" x2="2.6" y2="0.7" width="0.3048" layer="21"/>
</package>
<package name="C_DISC">
<pad name="1" x="0" y="0" drill="0.9" diameter="1.8"/>
<pad name="2" x="0" y="-5.08" drill="0.9" diameter="1.8"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="DIP28N">
<pad name="1" x="0" y="0" drill="0.8128" diameter="1.6"/>
<pad name="2" x="0" y="-2.54" drill="0.8128" diameter="1.6"/>
<pad name="3" x="0" y="-5.08" drill="0.8128" diameter="1.6"/>
<pad name="4" x="0" y="-7.62" drill="0.8128" diameter="1.6"/>
<pad name="5" x="0" y="-10.16" drill="0.8128" diameter="1.6"/>
<pad name="6" x="0" y="-12.7" drill="0.8128" diameter="1.6"/>
<pad name="7" x="0" y="-15.24" drill="0.8128" diameter="1.6"/>
<pad name="8" x="0" y="-17.78" drill="0.8128" diameter="1.6"/>
<pad name="9" x="0" y="-20.32" drill="0.8128" diameter="1.6"/>
<pad name="10" x="0" y="-22.86" drill="0.8128" diameter="1.6"/>
<pad name="11" x="0" y="-25.4" drill="0.8128" diameter="1.6"/>
<pad name="12" x="0" y="-27.94" drill="0.8128" diameter="1.6"/>
<pad name="13" x="0" y="-30.48" drill="0.8128" diameter="1.6"/>
<pad name="14" x="0" y="-33.02" drill="0.8128" diameter="1.6"/>
<pad name="15" x="7.62" y="-33.02" drill="0.8128" diameter="1.6"/>
<pad name="16" x="7.62" y="-30.48" drill="0.8128" diameter="1.6"/>
<pad name="17" x="7.62" y="-27.94" drill="0.8128" diameter="1.6"/>
<pad name="18" x="7.62" y="-25.4" drill="0.8128" diameter="1.6"/>
<pad name="19" x="7.62" y="-22.86" drill="0.8128" diameter="1.6"/>
<pad name="20" x="7.62" y="-20.32" drill="0.8128" diameter="1.6"/>
<pad name="21" x="7.62" y="-17.78" drill="0.8128" diameter="1.6"/>
<pad name="22" x="7.62" y="-15.24" drill="0.8128" diameter="1.6"/>
<pad name="23" x="7.62" y="-12.7" drill="0.8128" diameter="1.6"/>
<pad name="24" x="7.62" y="-10.16" drill="0.8128" diameter="1.6"/>
<pad name="25" x="7.62" y="-7.62" drill="0.8128" diameter="1.6"/>
<pad name="26" x="7.62" y="-5.08" drill="0.8128" diameter="1.6"/>
<pad name="27" x="7.62" y="-2.54" drill="0.8128" diameter="1.6"/>
<pad name="28" x="7.62" y="0" drill="0.8128" diameter="1.6"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="HC49">
<pad name="1" x="0" y="0" drill="0.8" diameter="1.6"/>
<pad name="2" x="4.88" y="0" drill="0.8" diameter="1.6"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="HDR2">
<pad name="1" x="0" y="0" drill="0.9" diameter="1.8"/>
<pad name="2" x="0" y="-2.54" drill="0.9" diameter="1.8"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="HDR6">
<pad name="1" x="0" y="0" drill="0.9" diameter="1.8"/>
<pad name="2" x="0" y="-2.54" drill="0.9" diameter="1.8"/>
<pad name="3" x="0" y="-5.08" drill="0.9" diameter="1.8"/>
<pad name="4" x="0" y="-7.62" drill="0.9" diameter="1.8"/>
<pad name="5" x="0" y="-10.16" drill="0.9" diameter="1.8"/>
<pad name="6" x="0" y="-12.7" drill="0.9" diameter="1.8"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="LED5">
<pad name="2" x="0" y="0" drill="0.9" diameter="1.8"/>
<pad name="1" x="2.54" y="0" drill="0.9" diameter="1.8"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="R_AXIAL">
<pad name="1" x="0" y="0" drill="0.8" diameter="1.6"/>
<pad name="2" x="10.16" y="0" drill="0.8" diameter="1.6"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
<package name="TO220">
<pad name="1" x="0" y="0" drill="1" diameter="2"/>
<pad name="2" x="2.54" y="0" drill="1" diameter="2"/>
<pad name="3" x="5.08" y="0" drill="1" diameter="2"/>
<text x="0" y="2.54" size="1.778" layer="25">&gt;NAME</text>
<text x="0" y="-2.54" size="1.778" layer="27">&gt;VALUE</text>
</package>
</packages>
<symbols>
<symbol name="ATMEGA328">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-35.56" width="0.254" layer="94"/>
<wire x1="12.7" y1="-35.56" x2="-12.7" y2="-35.56" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-35.56" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-39.37" size="1.778" layer="96">&gt;VALUE</text>
<pin name="RESET" x="-17.78" y="0" length="middle"/>
<pin name="RXD" x="-17.78" y="-2.54" length="middle"/>
<pin name="TXD" x="-17.78" y="-5.08" length="middle"/>
<pin name="PD2" x="-17.78" y="-7.62" length="middle"/>
<pin name="PD3" x="-17.78" y="-10.16" length="middle"/>
<pin name="PD4" x="-17.78" y="-12.7" length="middle"/>
<pin name="VCC" x="-17.78" y="-15.24" length="middle"/>
<pin name="GND1" x="-17.78" y="-17.78" length="middle"/>
<pin name="XTAL1" x="-17.78" y="-20.32" length="middle"/>
<pin name="XTAL2" x="-17.78" y="-22.86" length="middle"/>
<pin name="PD5" x="-17.78" y="-25.4" length="middle"/>
<pin name="PD6" x="-17.78" y="-27.94" length="middle"/>
<pin name="PD7" x="-17.78" y="-30.48" length="middle"/>
<pin name="PB0" x="-17.78" y="-33.02" length="middle"/>
<pin name="PB1" x="17.78" y="0" length="middle" rot="R180"/>
<pin name="PB2" x="17.78" y="-2.54" length="middle" rot="R180"/>
<pin name="MOSI" x="17.78" y="-5.08" length="middle" rot="R180"/>
<pin name="MISO" x="17.78" y="-7.62" length="middle" rot="R180"/>
<pin name="SCK" x="17.78" y="-10.16" length="middle" rot="R180"/>
<pin name="AVCC" x="17.78" y="-12.7" length="middle" rot="R180"/>
<pin name="AREF" x="17.78" y="-15.24" length="middle" rot="R180"/>
<pin name="GND2" x="17.78" y="-17.78" length="middle" rot="R180"/>
<pin name="PC0" x="17.78" y="-20.32" length="middle" rot="R180"/>
<pin name="PC1" x="17.78" y="-22.86" length="middle" rot="R180"/>
<pin name="PC2" x="17.78" y="-25.4" length="middle" rot="R180"/>
<pin name="PC3" x="17.78" y="-27.94" length="middle" rot="R180"/>
<pin name="SDA" x="17.78" y="-30.48" length="middle" rot="R180"/>
<pin name="SCL" x="17.78" y="-33.02" length="middle" rot="R180"/>
</symbol>
<symbol name="CAP">
<wire x1="-12.7" y1="0" x2="-1.27" y2="0" width="0.254" layer="94"/>
<wire x1="1.27" y1="0" x2="12.7" y2="0" width="0.254" layer="94"/>
<wire x1="-1.27" y1="-3.81" x2="-1.27" y2="3.81" width="0.254" layer="94"/>
<wire x1="1.27" y1="-3.81" x2="1.27" y2="3.81" width="0.254" layer="94"/>
<text x="-2.54" y="4.32" size="1.778" layer="95">&gt;NAME</text>
<text x="-2.54" y="-6.6" size="1.778" layer="96">&gt;VALUE</text>
<pin name="1" x="-17.78" y="0" length="middle"/>
<pin name="2" x="17.78" y="0" length="middle" rot="R180"/>
</symbol>
<symbol name="CAPP">
<wire x1="-12.7" y1="0" x2="-1.27" y2="0" width="0.254" layer="94"/>
<wire x1="1.78" y1="0" x2="12.7" y2="0" width="0.254" layer="94"/>
<wire x1="-1.27" y1="-3.81" x2="-1.27" y2="3.81" width="0.254" layer="94"/>
<wire x1="1.78" y1="-3.81" x2="1.78" y2="3.81" width="0.254" layer="94"/>
<wire x1="-5.59" y1="3.81" x2="-3.56" y2="3.81" width="0.254" layer="94"/>
<wire x1="-4.57" y1="2.79" x2="-4.57" y2="4.83" width="0.254" layer="94"/>
<text x="-2.54" y="4.32" size="1.778" layer="95">&gt;NAME</text>
<text x="-2.54" y="-6.6" size="1.778" layer="96">&gt;VALUE</text>
<pin name="+" x="-17.78" y="0" length="middle"/>
<pin name="-" x="17.78" y="0" length="middle" rot="R180"/>
</symbol>
<symbol name="HDR2">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-5.08" width="0.254" layer="94"/>
<wire x1="12.7" y1="-5.08" x2="-12.7" y2="-5.08" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-5.08" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-8.89" size="1.778" layer="96">&gt;VALUE</text>
<pin name="1" x="-17.78" y="0" length="middle"/>
<pin name="2" x="-17.78" y="-2.54" length="middle"/>
</symbol>
<symbol name="HDR6">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-15.24" width="0.254" layer="94"/>
<wire x1="12.7" y1="-15.24" x2="-12.7" y2="-15.24" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-15.24" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-19.05" size="1.778" layer="96">&gt;VALUE</text>
<pin name="1" x="-17.78" y="0" length="middle"/>
<pin name="2" x="-17.78" y="-2.54" length="middle"/>
<pin name="3" x="-17.78" y="-5.08" length="middle"/>
<pin name="4" x="-17.78" y="-7.62" length="middle"/>
<pin name="5" x="-17.78" y="-10.16" length="middle"/>
<pin name="6" x="-17.78" y="-12.7" length="middle"/>
</symbol>
<symbol name="L7805">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-7.62" width="0.254" layer="94"/>
<wire x1="12.7" y1="-7.62" x2="-12.7" y2="-7.62" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-7.62" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-11.43" size="1.778" layer="96">&gt;VALUE</text>
<pin name="IN" x="-17.78" y="0" length="middle"/>
<pin name="GND" x="-17.78" y="-2.54" length="middle"/>
<pin name="OUT" x="-17.78" y="-5.08" length="middle"/>
</symbol>
<symbol name="LED">
<wire x1="-12.7" y1="0" x2="-2.54" y2="0" width="0.254" layer="94"/>
<wire x1="2.54" y1="0" x2="12.7" y2="0" width="0.254" layer="94"/>
<wire x1="-2.54" y1="2.54" x2="-2.54" y2="-2.54" width="0.254" layer="94"/>
<wire x1="-2.54" y1="2.54" x2="2.54" y2="0" width="0.254" layer="94"/>
<wire x1="-2.54" y1="-2.54" x2="2.54" y2="0" width="0.254" layer="94"/>
<wire x1="2.54" y1="-2.54" x2="2.54" y2="2.54" width="0.254" layer="94"/>
<wire x1="1.02" y1="3.05" x2="3.05" y2="5.08" width="0.254" layer="94"/>
<wire x1="3.05" y1="5.08" x2="2.03" y2="4.83" width="0.254" layer="94"/>
<wire x1="3.05" y1="5.08" x2="2.79" y2="4.06" width="0.254" layer="94"/>
<wire x1="3.56" y1="2.54" x2="5.59" y2="4.57" width="0.254" layer="94"/>
<wire x1="5.59" y1="4.57" x2="4.57" y2="4.32" width="0.254" layer="94"/>
<wire x1="5.59" y1="4.57" x2="5.33" y2="3.56" width="0.254" layer="94"/>
<text x="-2.54" y="4.32" size="1.778" layer="95">&gt;NAME</text>
<text x="-2.54" y="-6.6" size="1.778" layer="96">&gt;VALUE</text>
<pin name="A" x="-17.78" y="0" length="middle"/>
<pin name="K" x="17.78" y="0" length="middle" rot="R180"/>
</symbol>
<symbol name="RES">
<wire x1="-12.7" y1="0" x2="-7.62" y2="0" width="0.254" layer="94"/>
<wire x1="7.62" y1="0" x2="12.7" y2="0" width="0.254" layer="94"/>
<wire x1="-7.62" y1="0" x2="-6.35" y2="1.78" width="0.254" layer="94"/>
<wire x1="-6.35" y1="1.78" x2="-3.81" y2="-1.78" width="0.254" layer="94"/>
<wire x1="-3.81" y1="-1.78" x2="-1.27" y2="1.78" width="0.254" layer="94"/>
<wire x1="-1.27" y1="1.78" x2="1.27" y2="-1.78" width="0.254" layer="94"/>
<wire x1="1.27" y1="-1.78" x2="3.81" y2="1.78" width="0.254" layer="94"/>
<wire x1="3.81" y1="1.78" x2="6.35" y2="-1.78" width="0.254" layer="94"/>
<wire x1="6.35" y1="-1.78" x2="7.62" y2="0" width="0.254" layer="94"/>
<text x="-2.54" y="4.32" size="1.778" layer="95">&gt;NAME</text>
<text x="-2.54" y="-6.6" size="1.778" layer="96">&gt;VALUE</text>
<pin name="1" x="-17.78" y="0" length="middle"/>
<pin name="2" x="17.78" y="0" length="middle" rot="R180"/>
</symbol>
<symbol name="XTAL16">
<wire x1="-12.7" y1="2.54" x2="12.7" y2="2.54" width="0.254" layer="94"/>
<wire x1="12.7" y1="2.54" x2="12.7" y2="-5.08" width="0.254" layer="94"/>
<wire x1="12.7" y1="-5.08" x2="-12.7" y2="-5.08" width="0.254" layer="94"/>
<wire x1="-12.7" y1="-5.08" x2="-12.7" y2="2.54" width="0.254" layer="94"/>
<text x="-12.7" y="3.81" size="1.778" layer="95">&gt;NAME</text>
<text x="-12.7" y="-8.89" size="1.778" layer="96">&gt;VALUE</text>
<pin name="1" x="-17.78" y="0" length="middle"/>
<pin name="2" x="-17.78" y="-2.54" length="middle"/>
</symbol>
</symbols>
<devicesets>
<deviceset name="ATMEGA328" prefix="U" uservalue="yes">
<gates>
<gate name="G$1" symbol="ATMEGA328" x="0" y="0"/>
</gates>
<devices>
<device name="" package="DIP28N">
<connects>
<connect gate="G$1" pin="AREF" pad="21"/>
<connect gate="G$1" pin="AVCC" pad="20"/>
<connect gate="G$1" pin="GND1" pad="8"/>
<connect gate="G$1" pin="GND2" pad="22"/>
<connect gate="G$1" pin="MISO" pad="18"/>
<connect gate="G$1" pin="MOSI" pad="17"/>
<connect gate="G$1" pin="PB0" pad="14"/>
<connect gate="G$1" pin="PB1" pad="15"/>
<connect gate="G$1" pin="PB2" pad="16"/>
<connect gate="G$1" pin="PC0" pad="23"/>
<connect gate="G$1" pin="PC1" pad="24"/>
<connect gate="G$1" pin="PC2" pad="25"/>
<connect gate="G$1" pin="PC3" pad="26"/>
<connect gate="G$1" pin="PD2" pad="4"/>
<connect gate="G$1" pin="PD3" pad="5"/>
<connect gate="G$1" pin="PD4" pad="6"/>
<connect gate="G$1" pin="PD5" pad="11"/>
<connect gate="G$1" pin="PD6" pad="12"/>
<connect gate="G$1" pin="PD7" pad="13"/>
<connect gate="G$1" pin="RESET" pad="1"/>
<connect gate="G$1" pin="RXD" pad="2"/>
<connect gate="G$1" pin="SCK" pad="19"/>
<connect gate="G$1" pin="SCL" pad="28"/>
<connect gate="G$1" pin="SDA" pad="27"/>
<connect gate="G$1" pin="TXD" pad="3"/>
<connect gate="G$1" pin="VCC" pad="7"/>
<connect gate="G$1" pin="XTAL1" pad="9"/>
<connect gate="G$1" pin="XTAL2" pad="10"/>
</connects>
<technologies>
<technology name=""/>
</technologies>
</device>
</devices>
</deviceset>
<deviceset name="CAP" prefix="U" uservalue="yes">
<gates>
<gate name="G$1" symbol="CAP" x="0" y="0"/>
</gates>
<devices>
<device name="" package="C_DISC">
<connects>
<connect gate="G$1" pin="1" pad="1"/>
<connect gate="G$1" pin="2" pad="2"/>
</connects>
<technologies>
<technology name=""/>
</technologies>
</device>
</devices>
</deviceset>
<deviceset name="CAPP" prefix="U" uservalue="yes">
<gates>
<gate name="G$1" symbol="CAPP" x="0" y="0"/>
</gates>
<devices>
<device name="" package="CP_RADIAL">
<connects>
<connect gate="G$1" pin="+" pad="1"/>
<connect gate="G$1" pin="-" pad="2"/>
</connects>
<technologies>
<technology name=""/>
</technologies>
</device>
</devices>
</deviceset>
<deviceset name="HDR2" prefix="U" uservalue="yes">
<gates>
<gate name="G$1" symbol="HDR2" x="0" y="0"/>
</gates>
<devices>
<device name="" package="HDR2">
<connects>
<connect gate="G$1" pin="1" pad="1"/>
<connect gate="G$1" pin="2" pad="2"/>
</connects>
<technologies>
<technology name=""/>
</technologies>
</device>
</devices>
</deviceset>
<deviceset name="HDR6" prefix="U" uservalue="yes">
<gates>
<gate name="G$1" symbol="HDR6" x="0" y="0"/>
</gates>
<devices>
<device name="" package="HDR6">
<connects>
<connect gate="G$1" pin="1" pad="1"/>
<connect gate="G$1" pin="2" pad="2"/>
<connect gate="G$1" pin="3" pad="3"/>
<connect gate="G$1" pin="4" pad="4"/>
<connect gate="G$1" pin="5" pad="5"/>
<connect gate="G$1" pin="6" pad="6"/>
</connects>
<technologies>
<technology name=""/>
</technologies>
</device>
</devices>
</deviceset>
<deviceset name="L7805" prefix="U" uservalue="yes">
<gates>
<gate name="G$1" symbol="L7805" x="0" y="0"/>
</gates>
<devices>
<device name="" package="TO220">
<connects>
<connect gate="G$1" pin="GND" pad="2"/>
<connect gate="G$1" pin="IN" pad="1"/>
<connect gate="G$1" pin="OUT" pad="3"/>
</connects>
<technologies>
<technology name=""/>
</technologies>
</device>
</devices>
</deviceset>
<deviceset name="LED" prefix="U" uservalue="yes">
<gates>
<gate name="G$1" symbol="LED" x="0" y="0"/>
</gates>
<devices>
<device name="" package="LED5">
<connects>
<connect gate="G$1" pin="A" pad="2"/>
<connect gate="G$1" pin="K" pad="1"/>
</connects>
<technologies>
<technology name=""/>
</technologies>
</device>
</devices>
</deviceset>
<deviceset name="RES" prefix="U" uservalue="yes">
<gates>
<gate name="G$1" symbol="RES" x="0" y="0"/>
</gates>
<devices>
<device name="" package="R_AXIAL">
<connects>
<connect gate="G$1" pin="1" pad="1"/>
<connect gate="G$1" pin="2" pad="2"/>
</connects>
<technologies>
<technology name=""/>
</technologies>
</device>
</devices>
</deviceset>
<deviceset name="XTAL16" prefix="U" uservalue="yes">
<gates>
<gate name="G$1" symbol="XTAL16" x="0" y="0"/>
</gates>
<devices>
<device name="" package="HC49">
<connects>
<connect gate="G$1" pin="1" pad="1"/>
<connect gate="G$1" pin="2" pad="2"/>
</connects>
<technologies>
<technology name=""/>
</technologies>
</device>
</devices>
</deviceset>
</devicesets>
</library>
</libraries>
<attributes>
</attributes>
<variantdefs>
</variantdefs>
<classes>
<class number="0" name="default" width="0" drill="0">
</class>
</classes>
<parts>
<part name="U1" library="p8x" deviceset="ATMEGA328" device="" value="ATMEGA328P-PU"/>
<part name="U2" library="p8x" deviceset="L7805" device="" value="7805"/>
<part name="Y1" library="p8x" deviceset="XTAL16" device="" value="16MHZ"/>
<part name="C1" library="p8x" deviceset="CAP" device="" value="22P"/>
<part name="C2" library="p8x" deviceset="CAP" device="" value="22P"/>
<part name="C3" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="C4" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="C5" library="p8x" deviceset="CAP" device="" value="100N"/>
<part name="C6" library="p8x" deviceset="CAPP" device="" value="10U"/>
<part name="C7" library="p8x" deviceset="CAPP" device="" value="10U"/>
<part name="R1" library="p8x" deviceset="RES" device="" value="10K"/>
<part name="R2" library="p8x" deviceset="RES" device="" value="330R"/>
<part name="R3" library="p8x" deviceset="RES" device="" value="1K"/>
<part name="LED1" library="p8x" deviceset="LED" device="" value="YEL"/>
<part name="LED2" library="p8x" deviceset="LED" device="" value="GRN"/>
<part name="J1" library="p8x" deviceset="HDR6" device="" value="FTDI"/>
<part name="J2" library="p8x" deviceset="HDR2" device="" value="7-12V DC"/>
<part name="R4" library="p8x" deviceset="RES" device="" value="330R"/>
<part name="LED3" library="p8x" deviceset="LED" device="" value="YEL"/>
<part name="R5" library="p8x" deviceset="RES" device="" value="330R"/>
<part name="LED4" library="p8x" deviceset="LED" device="" value="YEL"/>
</parts>
<sheets>
<sheet>
<plain>
<text x="0" y="40" size="3.81" layer="97">BREADBOARD ARDUINO (ATmega328P) - Cowork/Fusion workflow test</text>
</plain>
<instances>
<instance part="U1" gate="G$1" x="20" y="80" smashed="yes"/>
<instance part="U2" gate="G$1" x="65" y="80" smashed="yes"/>
<instance part="Y1" gate="G$1" x="110" y="80" smashed="yes"/>
<instance part="C1" gate="G$1" x="155" y="80" smashed="yes"/>
<instance part="C2" gate="G$1" x="200" y="80" smashed="yes"/>
<instance part="C3" gate="G$1" x="20" y="35" smashed="yes"/>
<instance part="C4" gate="G$1" x="65" y="35" smashed="yes"/>
<instance part="C5" gate="G$1" x="110" y="35" smashed="yes"/>
<instance part="C6" gate="G$1" x="155" y="35" smashed="yes"/>
<instance part="C7" gate="G$1" x="200" y="35" smashed="yes"/>
<instance part="R1" gate="G$1" x="20" y="-10" smashed="yes"/>
<instance part="R2" gate="G$1" x="65" y="-10" smashed="yes"/>
<instance part="R3" gate="G$1" x="110" y="-10" smashed="yes"/>
<instance part="LED1" gate="G$1" x="155" y="-10" smashed="yes"/>
<instance part="LED2" gate="G$1" x="200" y="-10" smashed="yes"/>
<instance part="J1" gate="G$1" x="20" y="-55" smashed="yes"/>
<instance part="J2" gate="G$1" x="65" y="-55" smashed="yes"/>
<instance part="R4" gate="G$1" x="110" y="-55" smashed="yes"/>
<instance part="LED3" gate="G$1" x="155" y="-55" smashed="yes"/>
<instance part="R5" gate="G$1" x="110" y="-100"/>
<instance part="LED4" gate="G$1" x="155" y="-100"/>
</instances>
<busses>
</busses>
<nets>
<net name="VCC" class="0">
<segment>
<pinref part="U1" gate="G$1" pin="VCC"/>
<wire x1="2.22" y1="64.76" x2="-2.86" y2="64.76" width="0.1524" layer="91"/>
<label x="-2.86" y="65.27" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="U1" gate="G$1" pin="AVCC"/>
<wire x1="37.78" y1="67.3" x2="42.86" y2="67.3" width="0.1524" layer="91"/>
<label x="42.86" y="67.81" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="U2" gate="G$1" pin="OUT"/>
<wire x1="47.22" y1="74.92" x2="42.14" y2="74.92" width="0.1524" layer="91"/>
<label x="42.14" y="75.43" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="J1" gate="G$1" pin="3"/>
<wire x1="2.22" y1="-60.08" x2="-2.86" y2="-60.08" width="0.1524" layer="91"/>
<label x="-2.86" y="-59.57" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C3" gate="G$1" pin="1"/>
<wire x1="2.22" y1="35" x2="-2.86" y2="35" width="0.1524" layer="91"/>
<label x="-2.86" y="35.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C4" gate="G$1" pin="1"/>
<wire x1="47.22" y1="35" x2="42.14" y2="35" width="0.1524" layer="91"/>
<label x="42.14" y="35.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C7" gate="G$1" pin="+"/>
<wire x1="182.22" y1="35" x2="177.14" y2="35" width="0.1524" layer="91"/>
<label x="177.14" y="35.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="R1" gate="G$1" pin="1"/>
<wire x1="2.22" y1="-10" x2="-2.86" y2="-10" width="0.1524" layer="91"/>
<label x="-2.86" y="-9.49" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="R3" gate="G$1" pin="1"/>
<wire x1="92.22" y1="-10" x2="87.14" y2="-10" width="0.1524" layer="91"/>
<label x="87.14" y="-9.49" size="1.778" layer="95"/>
</segment>
</net>
<net name="GND" class="0">
<segment>
<pinref part="U1" gate="G$1" pin="GND1"/>
<wire x1="2.22" y1="62.22" x2="-2.86" y2="62.22" width="0.1524" layer="91"/>
<label x="-2.86" y="62.73" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="U1" gate="G$1" pin="GND2"/>
<wire x1="37.78" y1="62.22" x2="42.86" y2="62.22" width="0.1524" layer="91"/>
<label x="42.86" y="62.73" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="U2" gate="G$1" pin="GND"/>
<wire x1="47.22" y1="77.46" x2="42.14" y2="77.46" width="0.1524" layer="91"/>
<label x="42.14" y="77.97" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="J1" gate="G$1" pin="1"/>
<wire x1="2.22" y1="-55" x2="-2.86" y2="-55" width="0.1524" layer="91"/>
<label x="-2.86" y="-54.49" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="J1" gate="G$1" pin="2"/>
<wire x1="2.22" y1="-57.54" x2="-2.86" y2="-57.54" width="0.1524" layer="91"/>
<label x="-2.86" y="-57.03" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="J2" gate="G$1" pin="2"/>
<wire x1="47.22" y1="-57.54" x2="42.14" y2="-57.54" width="0.1524" layer="91"/>
<label x="42.14" y="-57.03" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C1" gate="G$1" pin="2"/>
<wire x1="172.78" y1="80" x2="177.86" y2="80" width="0.1524" layer="91"/>
<label x="177.86" y="80.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C2" gate="G$1" pin="2"/>
<wire x1="217.78" y1="80" x2="222.86" y2="80" width="0.1524" layer="91"/>
<label x="222.86" y="80.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C3" gate="G$1" pin="2"/>
<wire x1="37.78" y1="35" x2="42.86" y2="35" width="0.1524" layer="91"/>
<label x="42.86" y="35.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C4" gate="G$1" pin="2"/>
<wire x1="82.78" y1="35" x2="87.86" y2="35" width="0.1524" layer="91"/>
<label x="87.86" y="35.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C6" gate="G$1" pin="-"/>
<wire x1="172.78" y1="35" x2="177.86" y2="35" width="0.1524" layer="91"/>
<label x="177.86" y="35.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C7" gate="G$1" pin="-"/>
<wire x1="217.78" y1="35" x2="222.86" y2="35" width="0.1524" layer="91"/>
<label x="222.86" y="35.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="LED1" gate="G$1" pin="K"/>
<wire x1="172.78" y1="-10" x2="177.86" y2="-10" width="0.1524" layer="91"/>
<label x="177.86" y="-9.49" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="LED2" gate="G$1" pin="K"/>
<wire x1="217.78" y1="-10" x2="222.86" y2="-10" width="0.1524" layer="91"/>
<label x="222.86" y="-9.49" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="LED3" gate="G$1" pin="K"/>
<wire x1="172.78" y1="-55" x2="177.86" y2="-55" width="0.1524" layer="91"/>
<label x="177.86" y="-54.49" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="LED4" gate="G$1" pin="K"/>
<wire x1="172.78" y1="-100" x2="177.86" y2="-100" width="0.1524" layer="91"/>
<label x="177.86" y="-99.49" size="1.778" layer="95"/>
</segment>
</net>
<net name="VIN" class="0">
<segment>
<pinref part="J2" gate="G$1" pin="1"/>
<wire x1="47.22" y1="-55" x2="42.14" y2="-55" width="0.1524" layer="91"/>
<label x="42.14" y="-54.49" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="U2" gate="G$1" pin="IN"/>
<wire x1="47.22" y1="80" x2="42.14" y2="80" width="0.1524" layer="91"/>
<label x="42.14" y="80.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C6" gate="G$1" pin="+"/>
<wire x1="137.22" y1="35" x2="132.14" y2="35" width="0.1524" layer="91"/>
<label x="132.14" y="35.51" size="1.778" layer="95"/>
</segment>
</net>
<net name="RESET" class="0">
<segment>
<pinref part="U1" gate="G$1" pin="RESET"/>
<wire x1="2.22" y1="80" x2="-2.86" y2="80" width="0.1524" layer="91"/>
<label x="-2.86" y="80.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="R1" gate="G$1" pin="2"/>
<wire x1="37.78" y1="-10" x2="42.86" y2="-10" width="0.1524" layer="91"/>
<label x="42.86" y="-9.49" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C5" gate="G$1" pin="2"/>
<wire x1="127.78" y1="35" x2="132.86" y2="35" width="0.1524" layer="91"/>
<label x="132.86" y="35.51" size="1.778" layer="95"/>
</segment>
</net>
<net name="DTR" class="0">
<segment>
<pinref part="J1" gate="G$1" pin="6"/>
<wire x1="2.22" y1="-67.7" x2="-2.86" y2="-67.7" width="0.1524" layer="91"/>
<label x="-2.86" y="-67.19" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C5" gate="G$1" pin="1"/>
<wire x1="92.22" y1="35" x2="87.14" y2="35" width="0.1524" layer="91"/>
<label x="87.14" y="35.51" size="1.778" layer="95"/>
</segment>
</net>
<net name="RXD" class="0">
<segment>
<pinref part="U1" gate="G$1" pin="RXD"/>
<wire x1="2.22" y1="77.46" x2="-2.86" y2="77.46" width="0.1524" layer="91"/>
<label x="-2.86" y="77.97" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="J1" gate="G$1" pin="4"/>
<wire x1="2.22" y1="-62.62" x2="-2.86" y2="-62.62" width="0.1524" layer="91"/>
<label x="-2.86" y="-62.11" size="1.778" layer="95"/>
</segment>
</net>
<net name="TXD" class="0">
<segment>
<pinref part="U1" gate="G$1" pin="TXD"/>
<wire x1="2.22" y1="74.92" x2="-2.86" y2="74.92" width="0.1524" layer="91"/>
<label x="-2.86" y="75.43" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="J1" gate="G$1" pin="5"/>
<wire x1="2.22" y1="-65.16" x2="-2.86" y2="-65.16" width="0.1524" layer="91"/>
<label x="-2.86" y="-64.65" size="1.778" layer="95"/>
</segment>
</net>
<net name="XTAL1" class="0">
<segment>
<pinref part="U1" gate="G$1" pin="XTAL1"/>
<wire x1="2.22" y1="59.68" x2="-2.86" y2="59.68" width="0.1524" layer="91"/>
<label x="-2.86" y="60.19" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="Y1" gate="G$1" pin="1"/>
<wire x1="92.22" y1="80" x2="87.14" y2="80" width="0.1524" layer="91"/>
<label x="87.14" y="80.51" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C1" gate="G$1" pin="1"/>
<wire x1="137.22" y1="80" x2="132.14" y2="80" width="0.1524" layer="91"/>
<label x="132.14" y="80.51" size="1.778" layer="95"/>
</segment>
</net>
<net name="XTAL2" class="0">
<segment>
<pinref part="U1" gate="G$1" pin="XTAL2"/>
<wire x1="2.22" y1="57.14" x2="-2.86" y2="57.14" width="0.1524" layer="91"/>
<label x="-2.86" y="57.65" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="Y1" gate="G$1" pin="2"/>
<wire x1="92.22" y1="77.46" x2="87.14" y2="77.46" width="0.1524" layer="91"/>
<label x="87.14" y="77.97" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="C2" gate="G$1" pin="1"/>
<wire x1="182.22" y1="80" x2="177.14" y2="80" width="0.1524" layer="91"/>
<label x="177.14" y="80.51" size="1.778" layer="95"/>
</segment>
</net>
<net name="D13" class="0">
<segment>
<pinref part="U1" gate="G$1" pin="SCK"/>
<wire x1="37.78" y1="69.84" x2="42.86" y2="69.84" width="0.1524" layer="91"/>
<label x="42.86" y="70.35" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="R2" gate="G$1" pin="1"/>
<wire x1="47.22" y1="-10" x2="42.14" y2="-10" width="0.1524" layer="91"/>
<label x="42.14" y="-9.49" size="1.778" layer="95"/>
</segment>
</net>
<net name="LED13" class="0">
<segment>
<pinref part="R2" gate="G$1" pin="2"/>
<wire x1="82.78" y1="-10" x2="87.86" y2="-10" width="0.1524" layer="91"/>
<label x="87.86" y="-9.49" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="LED1" gate="G$1" pin="A"/>
<wire x1="137.22" y1="-10" x2="132.14" y2="-10" width="0.1524" layer="91"/>
<label x="132.14" y="-9.49" size="1.778" layer="95"/>
</segment>
</net>
<net name="PWRLED" class="0">
<segment>
<pinref part="R3" gate="G$1" pin="2"/>
<wire x1="127.78" y1="-10" x2="132.86" y2="-10" width="0.1524" layer="91"/>
<label x="132.86" y="-9.49" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="LED2" gate="G$1" pin="A"/>
<wire x1="182.22" y1="-10" x2="177.14" y2="-10" width="0.1524" layer="91"/>
<label x="177.14" y="-9.49" size="1.778" layer="95"/>
</segment>
</net>
<net name="D8" class="0">
<segment>
<pinref part="U1" gate="G$1" pin="PB0"/>
<wire x1="2.22" y1="46.98" x2="-2.86" y2="46.98" width="0.1524" layer="91"/>
<label x="-2.86" y="47.49" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="R4" gate="G$1" pin="1"/>
<wire x1="92.22" y1="-55" x2="87.14" y2="-55" width="0.1524" layer="91"/>
<label x="87.14" y="-54.49" size="1.778" layer="95"/>
</segment>
</net>
<net name="LED8" class="0">
<segment>
<pinref part="R4" gate="G$1" pin="2"/>
<wire x1="127.78" y1="-55" x2="132.86" y2="-55" width="0.1524" layer="91"/>
<label x="140.48" y="-46.87" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="LED3" gate="G$1" pin="A"/>
<wire x1="137.22" y1="-55" x2="132.14" y2="-55" width="0.1524" layer="91"/>
<label x="132.14" y="-41.79" size="1.778" layer="95"/>
</segment>
</net>
<net name="D7" class="0">
<segment>
<pinref part="U1" gate="G$1" pin="PD7"/>
<wire x1="2.22" y1="49.52" x2="-2.86" y2="49.52" width="0.1524" layer="91"/>
<label x="-2.86" y="50.03" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="R5" gate="G$1" pin="1"/>
<wire x1="92.22" y1="-100" x2="87.14" y2="-100" width="0.1524" layer="91"/>
<label x="87.14" y="-99.49" size="1.778" layer="95"/>
</segment>
</net>
<net name="LED7" class="0">
<segment>
<pinref part="R5" gate="G$1" pin="2"/>
<wire x1="127.78" y1="-100" x2="132.86" y2="-100" width="0.1524" layer="91"/>
<label x="132.86" y="-99.49" size="1.778" layer="95"/>
</segment>
<segment>
<pinref part="LED4" gate="G$1" pin="A"/>
<wire x1="137.22" y1="-100" x2="132.14" y2="-100" width="0.1524" layer="91"/>
<label x="132.14" y="-99.49" size="1.778" layer="95"/>
</segment>
</net>
</nets>
</sheet>
</sheets>
</schematic>
</drawing>
</eagle>
