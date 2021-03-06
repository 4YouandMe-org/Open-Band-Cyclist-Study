//
//  ByteMathUtils.swift
//  OpenBandCylist
//
//  Copyright © 2020 4YouandMe. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import Foundation

public class ByteMathUtils {
    
    
    /// From the firmware code in Firmware_Peripheral.ino,
    /// There is a simple conversion from unisgned 32 bit to 4 bytes
    /// It is a simple bit shift operation that is easy to put back together the same way.
    /// uint32_t timestamp=millis();
    /// buf[3] = (uint8_t)timestamp;
    /// buf[2] = (uint8_t)(timestamp>>=8);
    /// buf[1] = (uint8_t)(timestamp>>=8);
    /// buf[0] = (uint8_t)(timestamp>>=8);
    public static func toOpenBandTimestamp(byte0: UInt8, byte1: UInt8, byte2: UInt8, byte3: UInt8) -> UInt32 {
        return UInt32(byte3) | (UInt32(byte2) << 8) | (UInt32(byte1) << 16) | (UInt32(byte0) << 24)
    }
    
    /// This is the same as the Timestamp logic, see above
    public static func toOpenBandPpgValue(byte0: UInt8, byte1: UInt8, byte2: UInt8, byte3: UInt8) -> UInt32 {
        return UInt32(byte3) | (UInt32(byte2) << 8) | (UInt32(byte1) << 16) | (UInt32(byte0) << 24)
    }
    
    /// The byte values are the storage buffers for the hardware accel sensor.
    /// From MPU9250_asukiaaa.cpp in the firmware project the calculation is:
    /// float MPU9250_asukiaaa::accelGet(uint8_t highIndex, uint8_t lowIndex) {
    /// int16_t v = ((int16_t) accelBuf[highIndex]) << 8 | accelBuf[lowIndex];
    ///   return ((float) -v) * accelRange / (float) 0x8000; // (float) 0x8000 == 32768.0
    /// }
    /// where the firmware code sets "accelRange" = 16.0
    public static func toOpenBandAccelFloat(byte0: UInt8, byte1: UInt8) -> Float {
        let acc =  Int16(bitPattern: ((UInt16(byte0) << 8) | UInt16(byte1)))
        return Float(-acc) * OpenBandConstants.accelScalingFactor
    }
}
