''**************************************
''
'' Driver for the TLC5940 chip for use on the Parallax Propeller
'' Adapted from the Brillidea Propeller Library
''
'' Written by Heath Paddock and Colin Harrington
''
''
''Description:
''This program sends grey scale data to TI TLC5940
''LED control chips wired in series.
''
''The Start function starts 2 cogs. The first runs the SendData
''function which constantly checks to see if there is any
''data to send to the TLC5940(s), and if there is, sends it.
''The second cog is handles the GSCLK and BLANK pins on the
''TLC5940(s).
''The program uses a two buffer system. The OffScreen
''Buffer is populated by the SetChannel and SetAllChannels functions.
''Each channel takes up a 16-bit word in the buffer, although
''only the lower 12-bits of each word are utilized. After setting
''any number of channels, a call to the Update function will trigger
''the "SendData" cog to copy the OffScreen Buffer to the OnScreen Buffer
''and then send the data to the TLC5940(s).
''Dot correction can also be set at any after Start. A call to SetDC or
''SetAllDC will update the TLC5940(s) immediately. No call to Update
''is required. The dot correction data is double buffered like the
''grey scale data. Although, if one was not making consecutive changes
''to dot correction values, one could probably get by with a single buffer.
''If your project does not require dot correction, you can connect the
''VPRG pin on the TLC(s) to ground.
''
''reference:
''      http://focus.ti.com/lit/ds/symlink/tlc5940.pdf (datasheet)
''      A big head start from Timothy D. Swieter, E.I. www.brilldea.com
''
''To Do:
''-convert serial shifting routine to ASM
''-code to do multiplexing
''**************************************
'
'    Basic Pin setup:
'
'    PROPELLER                                     TLC5940NT
'    ------------                                  ---u----
'                |                           OUT1 |1     28| OUT channel 0
'                |                           OUT2 |2     27|-> VPRG (pin 21)
'                |                           OUT3 |3     26|-> SIN (pin 19)
'                |                           OUT4 |4     25|-> SCLK (pin 20)
'                |                             .  |5     24|-> XLAT (pin 17)
'                |                             .  |6     23|-> BLANK (pin 18)
'              23|                             .  |7     22|-> GND
'              22|                             .  |8     21|-> VCC (+5V)
'              21|-> VPRG (pin 27)             .  |9     20|-> 2K Resistor -> GND
'              20|-> SCLK (pin 25)             .  |10    19|-> +5V (DCPRG)
'              19|-> SIN (pin 26)              .  |11    18|-> GSCLK (pin 16)
'              18|-> BLANK (pin 23)            .  |12    17|-> SOUT
'              17|-> XLAT (pin 24)             .  |13    16|-> XERR
'              16|-> GSCLK (pin 18)          OUT14|14    15| OUT channel 15
'    ------------                                  --------
'

CON

'***************************************
'  System Definitions      
'***************************************

  _OUTPUT       = 1             'Sets pin to output in DIRA register
  _INPUT        = 0             'Sets pin to input in DIRA register  
  _HIGH         = 1             'High=ON=1=3.3v DC
  _LOW          = 0             'Low=OFF=0=0v DC
  _GS_FLAG      = 1             'Send grey scale data to TLC
  _DC_FLAG      = 2             'Send dot correction data to TLC

  _NUM_TLCS     = 3             'Number of TLCs currently connected
  _NUM_TLC_CHANNELS = _NUM_TLCS * 16                       '16 channels per TLC

  _NUM_RGB_LEDS = 16            'Only used for bounds checking

VAR

  'Cog related
  long  cog                      'Values of cog running driver code
  long  stack[290]               'Stack space for spin cog

  'I/O pins
  long  SCLKpin                 'Serial clock line, data is lastched in on rising edge of clock
  long  SINpin                  'Serial data line into the chip
  long  XLATpin                 'Serial latch line, after all data clocked in, then a latch is performed
  long  GSCLKpin                'Reference clock for grey scale PWM control, counts when Blank is low
  long  BLANKpin                'Blanks all outputs when high.  GS counter is also reset.
  long  VPRGpin                 'When low the device is in GS mode.  When high, the device is in DC mode

  'Data related
  long  UpdateFlag                                      'Flag to signal a updates
  word  OffScreenBuffer[_NUM_TLC_CHANNELS]              'Working buffer to hold data
  word  OnScreenBuffer[_NUM_TLC_CHANNELS]               'Buffer of data to be sent to the TLC
  byte  OffScreenDCBuffer[_NUM_TLC_CHANNELS]            'Working buffer to hold dot correction data
  byte  OnScreenDCBuffer[_NUM_TLC_CHANNELS]             'Buffer of dot correction data to be sent to the TLC
  long baseOffset                                       'The number of TLC channels to skip. (This was relevant for my project, but probably won't be for yours. Set to 0)
  byte LastUpdateWasDC                                  'According to the datasheet, we need keep track of this




OBJ               'Object declaration to be located here

  GSCLK         : "GSCLK_Driver.spin"


PUB Start(_sclk, _sin, _xlat, _gsclk, _blank, _vprg, _baseOffset) : okay

'' Start TLC5940 driver - setup I/O pins, initiate variables, starts a cog
'' returns cog ID (1-8) if good or 0 if no good

  'Qualify the I/O values
  if lookdown(_sclk: 31..0)
    if lookdown(_sin: 31..0)
      if lookdown(_xlat: 31..0)
        if lookdown(_gsclk: 31..0)
          if lookdown(_blank: 31..0)
            if lookdown(_vprg: 31..0)
              if lookdown(_NUM_TLCS: 40..1)
                if lookdown(_baseOffset: _NUM_TLCS*16..0) 'TODO Edge case?
                  baseOffset := _baseOffset
                  LastUpdateWasDC := false

                  'Start a cog with the update/serial shifting routine
                  okay:= cog:= cognew(SendData(_sclk, _sin, _xlat, _gsclk, _blank, _vprg), @stack) + 1 'Returns 0-8 depending on success/failure


PUB Stop
'' Stops a cog running the TLC5940 driver (only allows one cog)
  if cog
    cogstop(cog~ - 1)




PUB SetChannel(_channel, _value) | temp0
''Set a given channel of the TLC to a given value (0-4095)

  if lookdown(_channel: _NUM_TLC_CHANNELS-1..0)                                 'Verify that the channel and value are within range
    if lookdown(_value: 4095..0)
      temp0 := @word[@OffScreenBuffer][_channel + baseOffset]                   'get the address where _ch is stored
      wordmove(temp0, @_value, 1)                                               'move _value to temp0


PUB SetAllChannels(_value) | i
''Set all channels of the TLC to a given value (0-4095)

  if lookdown(_value: 4095..0)                                                  'Verify _value is within range
    wordfill(@OffScreenBuffer + baseOffset, _value, _NUM_TLC_CHANNELS)          'Fill the entire array with word-sized copies of _value



PUB SetLED(_ledNum, _red, _grn, _blu) | temp0, temp1, temp2, channel
'' If you have RGB LEDs connected to the TLC(s), this function allows you
'' to set an RGB value for a specific RGB led Number.

  if lookdown(_ledNum: _NUM_RGB_LEDS-1..0)                                      'Verify the led number is within range
    if lookdown(_red: 4095..0)                                                  'Verify the values are within range
      if lookdown(_grn: 4095..0)
        if lookdown(_blu: 4095..0)
          channel := _ledNum * 3 + baseOffset                                   'Calculate the Offset from the base of the array
          temp0 := @word[@OffScreenBuffer][channel]                             'Retrieve the address for the red channel
          temp1 := @word[@OffScreenBuffer][channel + 1]                         'Retrieve the address for the green channel
          temp2 := @word[@OffScreenBuffer][channel + 2]                         'Retrieve the address for the blue channel

          wordmove(temp0, @_red, 1)                                             'Copy the _values to the buffer
          wordmove(temp1, @_grn, 1)                                             'TODO: Would this go faster with a single call to wordmove(temp0, @_colors, 3)?
          wordmove(temp2, @_blu, 1)



PUB Update
''Flag the other cog to update the TLC(s)

  UpdateFlag := _GS_FLAG                                                        'Add the GS bit to the UpdateFlag



PUB SetDC(_channel, _value)
''Set dot correction on a per-channel basis

  if lookdown(_channel: _NUM_TLC_CHANNELS-1..0)                                 'Qualify that the channel is correct
    if lookdown(_value: 63..0)                                                  'Qualify that the value is correct
      OffScreenDCBuffer[_channel + baseOffset] := _value                        'Set the value in the buffer
      UpdateFlag |= _DC_FLAG                                                    'Add DC data bit to the update flag



PUB SetAllDC(_value) | i
''Set dot correction on all channels to the same value

  if lookdown(_value: 63..0)                                                    'Qualify that the value is correct
    bytefill(@OffScreenDCBuffer + baseOffset, _value, _NUM_TLC_CHANNELS)        'Fill the array with the value
    UpdateFlag |= _DC_FLAG                                                      'Add DC flag bit to the update flag



PRI SendData(_sclk, _sin, _xlat, _gsclk, _blank, _vprg)

'' The main code that runs in another cog

  'Initialize the I/O and start a grey scale clock cog running
  'this is done from within this routine so that the proper cog
  'has the proper I/O configured.  
  Init(_sclk, _sin, _xlat, _gsclk, _blank, _vprg)

  'Loop forever sending data out
  repeat

    'The routine only sends data when there is an update
    'so it holds here until flagged to update
    repeat until UpdateFlag

    if (UpdateFlag & _GS_FLAG)                          'If the grey scale flag is set
      SendGSData                                        '  send the grey scale data
    if (UpdateFlag & _DC_FLAG)                          'If the dot correction flag is set
      SendDCData                                        '  send the dot correction data


PRI SendGSData | i, buffer
'' Serial communication with the TLC(s)

    UpdateFlag &= !_GS_FLAG                             'Clear the grey scale flag, but leave other flags in tact

    wordmove(@OnScreenBuffer, @OffScreenBuffer, _NUM_TLC_CHANNELS)              'Moves the off screen buffer to the on screen buffer

    repeat i from _NUM_TLC_CHANNELS-1 to 0              'Loop through values for all channels
      buffer := word[@OnScreenBuffer][i]                'Retreive the value for the current channel
      buffer <-= 20                                     'Since buffer is a long and we only need the lower 12 bits, rotate (skip) 16 unused bits + 4 unused bits

      repeat 12
        buffer <-= 1                                    'rotate the next bit into position
        outa[SINpin] := buffer & 1                      'set the pin to the bit
        outa[SCLKpin] := _HIGH                          'Toggle the clock pin high
        outa[SCLKpin] := _LOW                           'Toggle the clock pin low
    outa[XLATpin] := _HIGH                              'Toggle the latch pin high
    outa[XLATpin] := _LOW                               'Toggle the latch pin low

    if LastUpdateWasDC                                  'If this is the first GS cycle since DC was set
      LastUpdateWasDC := false
      outa[SCLKpin] := _HIGH                            'Toggle the clock high one more time (according to data sheet
      outa[SCLKpin] := _LOW                             'Toggle the clock low one more time (according to data sheet)

PRI SendDCData | i, buffer

    UpdateFlag &= !_DC_FLAG                             'Clear the dot correct flag, but leave other flags in tact

    bytemove(@OnScreenDCBuffer, @OffScreenDCBuffer, _NUM_TLC_CHANNELS)          'Moves the off screen buffer to the on screen buffer

    outa[VPRGpin] := _HIGH                              'Switch to dot correction mode

    repeat i from _NUM_TLC_CHANNELS-1 to 0
      buffer := byte[@OnScreenDCBuffer][i]
      buffer <-= 26                                     'Since buffer is a long and we only need the lower 12 bits, rotate (skip) 24 unused bits + 2 unused bits

      repeat 6
        buffer <-= 1                                    'rotate the next bit into position
        outa[SINpin] := buffer & 1                      'set the pin to the bit
        outa[SCLKpin] := _HIGH                          'Toggle the clock pin high
        outa[SCLKpin] := _LOW                           'Toggle the clock pin low

    outa[XLATpin] := _HIGH                              'Toggle the latch pin high
    outa[XLATpin] := _LOW                               'Toggle the latch pin low
    outa[VPRGpin] := _LOW                               'Return to grey scale mode

    LastUpdateWasDC := true                             'The GS cycle needs to know DC was just set

PRI Init(_sclk, _sin, _xlat, _gsclk, _blank, _vprg) | temp0

''Initializes the I/O based on parameters

  SCLKpin := _sclk              'Clock for data going to/from the chip
  dira[SCLKpin] := _OUTPUT
  outa[SCLKpin] := _LOW

  SINpin  := _sin               'Data going into the chip
  dira[SINpin] := _OUTPUT
  outa[SINpin] := _LOW

  XLATpin := _xlat              'Latch for the chip
  dira[XLATpin] := _OUTPUT
  outa[XLATpin] := _LOW

  VPRGpin := _vprg              'Multimode pin, see datasheet
  dira[VPRGpin] := _OUTPUT
  outa[VPRGpin] := _LOW

  GSCLK.Start(_gsclk, _blank)   'Start a cog that solely handles the grey scale clock (PWM)

'*************************************** 
{{
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │ │                                                                                                                              │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │ 
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}
