// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import "./lib/Lib_Keccak256.sol";
import "./lib/Lib_MerkleTrie.sol";
import { Lib_BytesUtils } from "./lib/Lib_BytesUtils.sol";

/// @title MIPS memory & Preimage oracle implementation
/// @notice Represent MIPS machine "state", including registers and memory-mapped I/O
contract MIPSMemory {
  /// @notice Add a node to MIPS memory merkle trie
  /// @param anything Value of a node
  function AddTrieNode(bytes calldata anything) public {
    Lib_MerkleTrie.GetTrie()[keccak256(anything)] = anything;
  }

  /*******************
   * Preimage Oracle *
   *******************/

  struct Preimage {
    uint64 length;
    mapping(uint => uint64) data;
  }

  mapping(bytes32 => Preimage) public preimage;

  /// @notice Revert with encoded hash and offset as an error message when trying to get missing preimage
  /// @param outhash Hash to find its preimage
  /// @param offset Offset of preimage bytes
  function MissingPreimageRevert(bytes32 outhash, uint offset) internal pure {
    Lib_BytesUtils.revertWithHex(abi.encodePacked(outhash, offset));
  }

  /// @notice Get the length of preimage of given hash
  /// @param outhash Hash to find its preimage
  /// @return Length of preimage
  function GetPreimageLength(bytes32 outhash) public view returns (uint32) {
    uint64 data = preimage[outhash].length;
    if (data == 0) {
      MissingPreimageRevert(outhash, 0);
    }
    return uint32(data);
  }

  /// @notice Get 32bits piece of preimage of given hash
  /// @param outhash Hash to find its preimage
  /// @param offset Bytes offset to locate data from preimage
  /// @return 32bits piece of preimage
  function GetPreimage(bytes32 outhash, uint offset) public view returns (uint32) {
    uint64 data = preimage[outhash].data[offset];
    if (data == 0) {
      MissingPreimageRevert(outhash, offset);
    }
    return uint32(data);
  }

  /// @notice Add 32bits piece of preimage to preimage oracle
  /// @param anything Full data in bytes array
  /// @param offset Bytes offset to locate data to store
  function AddPreimage(bytes calldata anything, uint offset) public {
    require(offset & 3 == 0, "offset must be 32-bit aligned");
    uint len = anything.length;
    require(offset < len, "offset can't be longer than input");
    Preimage storage p = preimage[keccak256(anything)];
    require(p.length == 0 || uint32(p.length) == len, "length is somehow wrong");
    p.length = (1 << 32) | uint64(uint32(len));
    p.data[offset] = (1 << 32) |
                     ((len <= (offset+0) ? 0 : uint32(uint8(anything[offset+0]))) << 24) |
                     ((len <= (offset+1) ? 0 : uint32(uint8(anything[offset+1]))) << 16) |
                     ((len <= (offset+2) ? 0 : uint32(uint8(anything[offset+2]))) << 8) |
                     ((len <= (offset+3) ? 0 : uint32(uint8(anything[offset+3]))) << 0);
  }

  // one per owner (at a time)

  struct LargePreimage {
    uint offset;
    uint len;
    uint32 data;
  }
  mapping(address => LargePreimage) public largePreimage;
  // sadly due to soldiity limitations this can't be in the LargePreimage struct
  mapping(address => uint64[25]) public largePreimageState;

  /// @notice Initiate adding large preimage process
  /// @param offset Bytes offset to locate data to store
  function AddLargePreimageInit(uint offset) public {
    require(offset & 3 == 0, "offset must be 32-bit aligned");
    Lib_Keccak256.CTX memory c;
    Lib_Keccak256.keccak_init(c);
    largePreimageState[msg.sender] = c.A;
    largePreimage[msg.sender].offset = offset;
    largePreimage[msg.sender].len = 0;
  }

  /// @notice Add a chunk of large preimage
  ///         input 136 bytes, as many times as you'd like
  ///         Uses about 500k gas, 3435 gas/byte
  /// @param dat Chunk of large preimage. Must be 136 bytes.
  function AddLargePreimageUpdate(bytes calldata dat) public {
    require(dat.length == 136, "update must be in multiples of 136");
    // sha3_process_block
    Lib_Keccak256.CTX memory c;
    c.A = largePreimageState[msg.sender];

    int offset = int(largePreimage[msg.sender].offset) - int(largePreimage[msg.sender].len);
    if (offset >= 0 && offset < 136) {
      largePreimage[msg.sender].data = fbo(dat, uint(offset));
    }
    Lib_Keccak256.sha3_xor_input(c, dat);
    Lib_Keccak256.sha3_permutation(c);
    largePreimageState[msg.sender] = c.A;
    largePreimage[msg.sender].len += 136;
  }

  /// @notice Get the result of adding large preimage process
  /// @param idat Last chunk of large preimage
  /// @return Hash of large preimage
  /// @return Length of large preimage
  /// @return 32bits piece of preimage to store
  function AddLargePreimageFinal(bytes calldata idat) public view returns (bytes32, uint32, uint32) {
    require(idat.length < 136, "final must be less than 136");
    int offset = int(largePreimage[msg.sender].offset) - int(largePreimage[msg.sender].len);
    require(offset < int(idat.length), "offset must be less than length");
    Lib_Keccak256.CTX memory c;
    c.A = largePreimageState[msg.sender];

    bytes memory dat = new bytes(136);
    for (uint i = 0; i < idat.length; i++) {
      dat[i] = idat[i];
    }
    uint len = largePreimage[msg.sender].len + idat.length;
    uint32 data = largePreimage[msg.sender].data;
    if (offset >= 0) {
      data = fbo(dat, uint(offset));
    }
    dat[135] = bytes1(uint8(0x80));
    dat[idat.length] |= bytes1(uint8(0x1));

    Lib_Keccak256.sha3_xor_input(c, dat);
    Lib_Keccak256.sha3_permutation(c);

    bytes32 outhash = Lib_Keccak256.get_hash(c);
    require(len < 0x10000000, "max length is 32-bit");
    return (outhash, uint32(len), data);
  }

  /// @notice Finish adding large preimage process
  /// @param idat Last chunk of large preimage
  function AddLargePreimageFinalSaved(bytes calldata idat) public {
    bytes32 outhash;
    uint32 len;
    uint32 data;
    (outhash, len, data) = AddLargePreimageFinal(idat);

    Preimage storage p = preimage[outhash];
    require(p.length == 0 || uint32(p.length) == len, "length is somehow wrong");
    require(largePreimage[msg.sender].offset < len, "offset is somehow beyond length");
    p.length = (1 << 32) | uint64(len);
    p.data[largePreimage[msg.sender].offset] = (1 << 32) | data;
  }

  /*********************************
   * Encoding & Decoding Functions *
   *********************************/

  /// @notice Decode 32bits value to bytes array
  /// @param dat Encoded 32bits value
  /// @return Decoded bytes array
  function tb(uint32 dat) internal pure returns (bytes memory) {
    bytes memory ret = new bytes(4);
    ret[0] = bytes1(uint8(dat >> 24));
    ret[1] = bytes1(uint8(dat >> 16));
    ret[2] = bytes1(uint8(dat >> 8));
    ret[3] = bytes1(uint8(dat >> 0));
    return ret;
  }

  /// @notice Encode bytes array to 32bits value
  /// @param dat Bytes array to encode
  /// @return Encoded 32bits value
  function fb(bytes memory dat) internal pure returns (uint32) {
    require(dat.length == 4, "wrong length value");
    uint32 ret = uint32(uint8(dat[0])) << 24 |
                 uint32(uint8(dat[1])) << 16 |
                 uint32(uint8(dat[2])) << 8 |
                 uint32(uint8(dat[3]));
    return ret;
  }

  /// @notice Encode a piece of bytes array to 32bits value
  /// @param dat Bytes array to encode
  /// @param offset Bytes offset to locate a piece to encode
  /// @return Encoded 32bits value
  function fbo(bytes memory dat, uint offset) internal pure returns (uint32) {
    uint32 ret = uint32(uint8(dat[offset+0])) << 24 |
                 uint32(uint8(dat[offset+1])) << 16 |
                 uint32(uint8(dat[offset+2])) << 8 |
                 uint32(uint8(dat[offset+3]));
    return ret;
  }

  /*************************
   * MIPS Memory Functions *
   *************************/

  /// @notice Write a 32bits value to the given address of MIPS memory
  /// @param stateHash Known MIPS state root hash
  /// @param addr MIPS memory address
  /// @param value Value to write
  /// @return New MIPS state root hash
  function WriteMemory(bytes32 stateHash, uint32 addr, uint32 value) public returns (bytes32) {
    require(addr & 3 == 0, "write memory must be 32-bit aligned");
    return Lib_MerkleTrie.update(tb(addr>>2), tb(value), stateHash);
  }

  /// @notice Write a 32bytes value to the given address range of MIPS memory
  /// @param stateHash Known MIPS stsate root hash
  /// @param addr MIPS memory address
  /// @param val Value to write
  /// @return New MIPS state root hash
  function WriteBytes32(bytes32 stateHash, uint32 addr, bytes32 val) public returns (bytes32) {
    for (uint32 i = 0; i < 32; i += 4) {
      uint256 tv = uint256(val>>(224-(i*8)));
      stateHash = WriteMemory(stateHash, addr+i, uint32(tv));
    }
    return stateHash;
  }

  // TODO: refactor writeMemory function to not need these
  event DidStep(bytes32 stateHash);

  /// @notice Write 32bits value to the given address of MIPS memory and emit an event
  /// @param stateHash Known MIPS state root hash
  /// @param addr MIPS memory address
  /// @param value Value to write
  /// @return New MIPS state root hash
  function WriteMemoryWithReceipt(bytes32 stateHash, uint32 addr, uint32 value) public {
    bytes32 newStateHash = WriteMemory(stateHash, addr, value);
    emit DidStep(newStateHash);
  }

  /// @notice Write 32bytes value to the given address range of MIPS memory and emit an event
  /// @param stateHash Known MIPS state root hash
  /// @param addr MIPS memory address
  /// @param val Value to write
  /// @return New MIPS state root hash
  function WriteBytes32WithReceipt(bytes32 stateHash, uint32 addr, bytes32 value) public {
    bytes32 newStateHash = WriteBytes32(stateHash, addr, value);
    emit DidStep(newStateHash);
  }

  /// @notice Read 32bytes value from the given address range of MIPS memory
  /// @dev needed for preimage oracle
  /// @param stateHash MIPS state root hash
  /// @addr MIPS memory address
  /// @return Value from memory
  function ReadBytes32(bytes32 stateHash, uint32 addr) public view returns (bytes32) {
    uint256 ret = 0;
    for (uint32 i = 0; i < 32; i += 4) {
      ret <<= 32;
      ret |= uint256(ReadMemory(stateHash, addr+i));
    }
    return bytes32(ret);
  }

  /// @notice Read 32bits value from the given address of MIPS memory
  /// @dev If the address is in preimage oracle memory range, read data from preimage oracle.
  /// @param stateHash MIPS state root hash
  /// @addr MIPS memory address
  /// @return Value from memory
  function ReadMemory(bytes32 stateHash, uint32 addr) public view returns (uint32) {
    require(addr & 3 == 0, "read memory must be 32-bit aligned");

    // zero register is always 0
    if (addr == 0xc0000000) {
      return 0;
    }

    // MMIO preimage oracle
    if (addr >= 0x31000000 && addr < 0x32000000) {
      bytes32 pihash = ReadBytes32(stateHash, 0x30001000);
      if (pihash == keccak256("")) {
        // both the length and any data are 0
        return 0;
      }
      if (addr == 0x31000000) {
        return uint32(GetPreimageLength(pihash));
      }
      return GetPreimage(pihash, addr-0x31000004);
    }

    bool exists;
    bytes memory value;
    (exists, value) = Lib_MerkleTrie.get(tb(addr>>2), stateHash);

    if (!exists) {
      // this is uninitialized memory
      return 0;
    } else {
      return fb(value);
    }
  }

}