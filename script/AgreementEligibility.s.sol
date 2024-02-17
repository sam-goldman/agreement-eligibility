// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Script, console2 } from "forge-std/Script.sol";
import { AgreementEligibility } from "../src/AgreementEligibility.sol";
import { Sphinx, Network } from "@sphinx-labs/contracts/SphinxPlugin.sol";

contract Deploy is Script, Sphinx {
  address public implementation;
  bytes32 public SALT = bytes32(abi.encode(0x4a75)); // "hats"

  // default values
  bool private verbose = true;
  string private version = "0.1.0"; // increment with each deployment

  function setUp() public virtual {
      sphinxConfig.owners = [address(0)]; // Add owner address
      sphinxConfig.orgId = ""; // Add org ID
      sphinxConfig.mainnets = [
        Network.ethereum
      ];
      sphinxConfig.testnets = [
        Network.arbitrum_sepolia,
        Network.optimism_sepolia,
        Network.polygon_mumbai
      ];
      sphinxConfig.projectName = "Agreement_Eligibility";
      sphinxConfig.threshold = 1;
  }

  /// @notice Override default values, if desired
  function prepare(bool _verbose, string memory _version) public {
    verbose = _verbose;
    version = _version;
  }

  function run() public sphinx {
    implementation = address(new AgreementEligibility{ salt: SALT }(version));

    if (verbose) {
      console2.log("Implementation:", implementation);
    }
  }
}

// forge script script/AgreementClaimsHatter.s.sol -f ethereum --broadcast --verify

/* 
forge verify-contract --chain-id 5 --num-of-optimizations 1000000 --watch --constructor-args $(cast abi-encode \
"constructor(string)" "0.0.1" ) --compiler-version v0.8.19 0xE43C43d93B22EB3CB0aEB05746094c0925FDC262 \
src/AgreementClaimsHatter.sol:AgreementClaimsHatter --etherscan-api-key $ETHERSCAN_KEY 
*/
