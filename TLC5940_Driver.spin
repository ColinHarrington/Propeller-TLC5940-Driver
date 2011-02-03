''**************************************
''
''  TLC5940 Driver Ver. 00.1
''
''  Updated: February 2, 2011
''
''  Heath Paddock
''  Colin Harrington
''
''Description:
''This program sends grey scale data to TI TLC5940
''LED control chips wired in series.
''
''This program launches a cog, configures the I/O.
''The data is loaded into a
''buffer.  There is a two buffer system.  Data is loaded
''into the offscreen buffer.  When ready the offscreen buffer
''is copied to the onscreen buffer.  This program runs at
''about a 40+frames/second.
''
''reference:
''      tlc5940.pdf (Datasheet for chip)
''      various code found on Parallax Propeller Forum
''
''To Do:
''-add dot correction capability
''-convert serial shifting routine to ASM?
''
''**************************************

CON
'***************************************
'  Hardware related settings
'***************************************
  _clkmode = xtal1 + pll16x                             'Use the PLL to multiple the external clock by 16
  _xinfreq = 5_000_000                                  'An external clock of 5MHz. is used (80MHz. operation)
  
'***************************************
'  System Definitions      
'***************************************

  _OUTPUT       = 1             'Sets pin to output in DIRA register
  _INPUT        = 0             'Sets pin to input in DIRA register  
  _HIGH         = 1             'High=ON=1=3.3v DC
  _ON           = 1
  _LOW          = 0             'Low=OFF=0=0v DC
  _OFF          = 0
  _ENABLE       = 1             'Enable (turn on) function/mode
  _DISABLE      = 0             'Disable (turn off) function/mode
  _GS_FLAG      = 1             'Send grayscale data to TLC
  _DC_FLAG      = 2             'Send dot correction data to TLC

  _NUM_TLCS     = 3             'Number of TLCs currently connected
  _NUM_TLC_CHANNELS = _NUM_TLCS * 16                       '12 bits in a channel * 16 channels

  _NUM_LEDS = 16

VAR

  'Cog related
  long  cog                      'Values of cog running driver code
  long  stack[290]               'Stack space for spin cog

  'I/O pins
  long  SCLKpin                 'Serial clock line, data is lastched in on rising edge of clock
  long  SINpin                  'Serial data line into the chip
  long  XLATpin                 'Serial latch line, after all data clocked in, then a latch is performed
  long  GSCLKpin                'Reference clock for grayscale PWM control, counts when Blank is low
  long  BLANKpin                'Blanks all outputs when high.  GS counter is also reset.
  long  VPRGpin                 'When low the device is in GS mode.  When high, the device is in DC mode

  'Data related
  long  UpdateFlag                                      'Flag to signal a screen update
'  word  OffScreenBuffer[_NUM_TLC_CHANNELS]              'Working buffer to hold data
  word OffScreenBufferAddr                              'Address of the OffScreenBuffer
  word  OnScreenBuffer[_NUM_TLC_CHANNELS]               'Buffer of data to be sent to the TLC
  byte  OffScreenDCBuffer[_NUM_TLC_CHANNELS]            'Working buffer to hold dot correction data
  byte  OnScreenDCBuffer[_NUM_TLC_CHANNELS]             'Buffer of dot correction data to be sent to the TLC
  long baseOffset
  byte LastUpdateWasDC




OBJ               'Object declaration to be located here

  GSCLK         : "GSCLK_Driver.spin"


PUB Start(_sclk, _sin, _xlat, _gsclk, _blank, _vprg, _baseOffset, _offScreenBuff) : okay

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
                if lookdown(_baseOffset: _NUM_TLCS*16..0) 'TODO Corner case?
                  baseOffset := _baseOffset
                  LastUpdateWasDC := _OFF
                  OffScreenBufferAddr := _offScreenBuff

                  'Start a cog with the update/serial shifting routine
                  okay:= cog:= cognew(SendData(_sclk, _sin, _xlat, _gsclk, _blank, _vprg), @stack) + 1 'Returns 0-8 depending on success/failure


PUB Stop

'' Stops a cog running the TLC5940 driver (only allows one cog)

  if cog
    cogstop(cog~ -  1)

PUB SetLED(_ledNum, _red, _grn, _blu) | temp0, temp1, temp2, channel
'' Set an RGB value for a specific channel - 8 bit for each color
  'Qualify that the channel and value must be correct
  if lookdown(_ledNum: _NUM_LEDS-1..0)
    if lookdown(_red: 4095..0)
      if lookdown(_grn: 4095..0)
        if lookdown(_blu: 4095..0)
          channel := _ledNum * 3 + baseOffset
          'Calculate the address where to move the data
            temp0 := @word[OffScreenBufferAddr][channel]
            temp1 := @word[OffScreenBufferAddr][channel + 1]
            temp2 := @word[OffScreenBufferAddr][channel + 2]

          'Move the data
          wordmove(temp0, @_red, 1)
          wordmove(temp1, @_grn, 1)                     'TODO: Would this go faster with a single call to wordmove(temp0, @_colors, 3)?
          wordmove(temp2, @_blu, 1)


PUB SetChannel(_ch, _val) | temp0
  if lookdown(_ch: _NUM_TLC_CHANNELS-1..0)                                      'Qualify that the channel and value must be correct
    if lookdown(_val: 4095..0)
      temp0 := @word[OffScreenBufferAddr][_ch + baseOffset]                        'get the address where _ch is stored
      wordmove(temp0, @_val, 1)                                                 'move value to temp0



PUB SetAllChannels(_value) | i
  if lookdown(_value: 4095..0)
    wordfill(OffScreenBufferAddr + baseOffset, _value, _NUM_TLC_CHANNELS)            'Fill the entire array with word-sized copies of _value



PUB Update

  UpdateFlag := _GS_FLAG        'Add the GS bit to the UpdateFlag
  

PUB SetDC(_channel, _value)
  if lookdown(_channel: _NUM_TLC_CHANNELS-1..0)                                 'Qualify that the channel is correct
    if lookdown(_value: 63..0)                                                  'Qualify that the value is correct
      OffScreenDCBuffer[_channel + baseOffset] := _value                        'Set the value in the buffer
      UpdateFlag |= _DC_FLAG                                                    'Add DC data bit to the update flag

PUB SetAllDC(_value) | i
  if lookdown(_value: 63..0)                                                    'Qualify that the value is correct
    bytefill(@OffScreenDCBuffer + baseOffset, _value, _NUM_TLC_CHANNELS)        'Fill the array with the value
    UpdateFlag |= _DC_FLAG                                                      'Add DC flag bit to the update flag



PRI SendData(_sclk, _sin, _xlat, _gsclk, _blank, _vprg)

'' The main code that runs in another cog
'' An update is sent of grey scale data in the OnScreenBuffer

  'Initialize the I/O and start a grey scale clock cog running
  'this is done from within this routine so that the proper cog
  'has the proper I/O configured.  
  Init(_sclk, _sin, _xlat, _gsclk, _blank, _vprg)

  'Loop forever sending data out
  repeat

    'The routine only sends data when there is an update
    'so it holds here until flagged to update
    repeat until UpdateFlag

    if (UpdateFlag & _GS_FLAG)                          'If the grayscale flag is set
      SendGSData                                        '  send the grayscale data
    if (UpdateFlag & _DC_FLAG)                          'If the dot correction flag is set
      SendDCData                                        '  send the grayscale data


PRI SendGSData | i, buffer

    'Clear the grayscale flag, but leave other flags in tact
    UpdateFlag &= !_GS_FLAG

     'Moves the off screen buffer to the on screen buffer
    wordmove(@OnScreenBuffer, OffScreenBufferAddr, _NUM_TLC_CHANNELS)

    repeat i from _NUM_TLC_CHANNELS-1 to 0
      buffer := word[@OnScreenBuffer][i]
      buffer <-= 20                                     'rotate (skip) 16 unused bits + 4 unused bits

      repeat 12
        buffer <-= 1
        outa[SINpin] := buffer & 1                      'rotate the next bit into position
        outa[SCLKpin] := _HIGH                          'Toggle the clock pin high
        outa[SCLKpin] := _LOW                           'Toggle the clock pin low
    outa[XLATpin] := _HIGH                              'Toggle the latch pin high
    outa[XLATpin] := _LOW                               'Toggle the latch pin low

    if LastUpdateWasDC                                  'If this is the first GS cycle since DC was set
      LastUpdateWasDC := false
      outa[SCLKpin] := _HIGH                            'Toggle the clock high one more time (according to data sheet
      outa[SCLKpin] := _LOW                             'Toggle the clock low one more time (according to data sheet)

PRI SendDCData | i, buffer

    'Clear the dot correct flag, but leave other flags in tact
    UpdateFlag &= !_DC_FLAG

     'Moves the off screen buffer to the on screen buffer
    bytemove(@OnScreenDCBuffer, @OffScreenDCBuffer, _NUM_TLC_CHANNELS)

    outa[VPRGpin] := _HIGH                              'Switch to dot correction mode

    repeat i from _NUM_TLC_CHANNELS-1 to 0
      buffer := byte[@OnScreenDCBuffer][i]
      buffer <-= 26                                     'rotate (skip) 24 unused bits + 2 unused bits

      repeat 6
        buffer <-= 1                                    'rotate the next bit into position
        outa[SINpin] := buffer & 1                      'set the pin to the bit
        outa[SCLKpin] := _HIGH                          'Toggle the clock pin high
        outa[SCLKpin] := _LOW                           'Toggle the clock pin low

    outa[XLATpin] := _HIGH                              'Toggle the latch pin high
    outa[XLATpin] := _LOW                               'Toggle the latch pin low
    outa[VPRGpin] := _LOW                               'Return to grayscale mode

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

  'Begin routines in seperate cog, done last so that zeros are in the registers before
  'data clocking so the display doesn't blink or change wildly on startup
  GSCLK.Start(_gsclk, _blank)   'Start a cog that solely handles the greyscale clock (PWM)


PRI Pause(Duration)
'' Pause execution in milliseconds.
'' Duration = number of milliseconds to delay

  waitcnt(((clkfreq / 1_000 * Duration - 3932) #> 381) + cnt)

DAT                             'Assembly code and initialized variables
''None at this time
