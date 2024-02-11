// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";

import {
  AgreementEligibility,
  AgreementEligibility_NotOwner,
  AgreementEligibility_NotArbitrator
} from "../src/AgreementEligibility.sol";
import { Deploy } from "../script/AgreementEligibility.s.sol";
import {
  IHats,
  HatsModuleFactory,
  deployModuleFactory,
  deployModuleInstance
} from "lib/hats-module/src/utils/DeployFunctions.sol";
import { MultiClaimsHatter } from "multi-claims-hatter/MultiClaimsHatter.sol";

contract AgreementEligibilityTest is Deploy, Test {
  // variables inhereted from Deploy script
  // address public implementation;
  // bytes32 public SALT;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 17_671_864;
  IHats public constant HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137); // v1.hatsprotocol.eth

  string public FACTORY_VERSION = "factory test version";
  string public MODULE_VERSION = "module test version";

  event AgreementEligibilityHatter_HatClaimedWithAgreement(address claimer, uint256 hatId, string agreement);
  event AgreementEligibilityHatter_AgreementSigned(address signer, string agreement);
  event AgreementEligibilityHatter_AgreementSet(string agreement, uint256 grace);

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy via the script
    Deploy.prepare(false, MODULE_VERSION); // set first param to true to log deployment addresses
    Deploy.run();
  }
}

contract WithInstanceTest is AgreementEligibilityTest {
  enum ClaimType {
    NotClaimable,
    Claimable,
    ClaimableFor
  }

  HatsModuleFactory public factory;
  AgreementEligibility public instance;
  MultiClaimsHatter public claimsHatter;

  bytes public otherImmutableArgs;
  bytes public initData;

  uint256 public tophat;
  uint256 public claimableHat;
  // owner hat will be the tophat
  uint256 public arbitratorHat;
  uint256 public registrarHat;
  address public eligibility = makeAddr("eligibility");
  address public toggle = makeAddr("toggle");
  address public dao = makeAddr("dao");
  address public arbitrator = makeAddr("arbitrator");
  address public claimer1 = makeAddr("claimer1");
  address public claimer2 = makeAddr("claimer2");
  address public nonWearer = makeAddr("nonWearer");

  string public agreement;
  uint256 public gracePeriod;
  uint256 public currentAgreementId;

  function deployAgreementEligibilityInstance(
    uint256 _claimableHat,
    uint256 _ownerHat,
    uint256 _arbitratorHat,
    address _claimsHatter,
    string memory _agreement
  ) public returns (AgreementEligibility) {
    // encode the other immutable args as packed bytes
    otherImmutableArgs = abi.encodePacked(_ownerHat, _arbitratorHat, _claimsHatter);
    // encoded the initData as unpacked bytes
    initData = abi.encode(_agreement);
    // deploy the instance
    return AgreementEligibility(
      deployModuleInstance(factory, address(implementation), _claimableHat, otherImmutableArgs, initData)
    );
  }

  function deployMultiClaimsHatterInstance(
    uint256 _hatId,
    uint256[] memory _claimableHats,
    ClaimType[] memory _claimTypes
  ) public returns (MultiClaimsHatter) {
    // encoded the initData as unpacked bytes
    initData = abi.encode(_claimableHats, _claimTypes);
    // deploy the instance
    return MultiClaimsHatter(
      deployModuleInstance(factory, address(0xB985eA1be961f7c4A4C45504444C02c88c4fdEF9), _hatId, "", initData)
    );
  }

  function setUp() public virtual override {
    super.setUp();

    // deploy the hats module factory
    factory = deployModuleFactory(HATS, SALT, FACTORY_VERSION);

    // set up hats
    tophat = HATS.mintTopHat(dao, "tophat", "dao.eth/tophat");
    vm.startPrank(dao);
    registrarHat = HATS.createHat(tophat, "registrarHat", 1, eligibility, toggle, true, "dao.eth/registrarHat");
    claimableHat = HATS.createHat(registrarHat, "claimableHat", 50, eligibility, toggle, true, "dao.eth/claimableHat");
    arbitratorHat = HATS.createHat(tophat, "arbitratorHat", 1, eligibility, toggle, true, "dao.eth/arbitratorHat");
    HATS.mintHat(arbitratorHat, arbitrator);
    vm.stopPrank();

    // deploy an instance of multi calims hatter
    uint256[] memory claimableHats = new uint256[](1);
    ClaimType[] memory claimTypes = new ClaimType[](1);
    claimableHats[0] = claimableHat;
    claimTypes[0] = ClaimType.ClaimableFor;
    claimsHatter = deployMultiClaimsHatterInstance(registrarHat, claimableHats, claimTypes);
    vm.prank(dao);
    HATS.mintHat(registrarHat, address(claimsHatter));

    // set up initial agreement
    agreement = "this is the first agreement";
    gracePeriod = 9 days; // the min + 2 days

    // deploy the instance
    instance = deployAgreementEligibilityInstance(claimableHat, tophat, arbitratorHat, address(claimsHatter), agreement);

    // set instance as claimableHat's eligibility module
    vm.prank(dao);
    HATS.changeHatEligibility(claimableHat, address(instance));
  }
}

contract Deployment is WithInstanceTest {
  function test_version() public {
    assertEq(instance.version(), MODULE_VERSION);
  }

  function test_implementation() public {
    assertEq(address(instance.IMPLEMENTATION()), address(implementation));
  }

  function test_hats() public {
    assertEq(address(instance.HATS()), address(HATS));
  }

  function test_claimableHat() public {
    assertEq(instance.hatId(), claimableHat);
  }

  function test_ownerHat() public {
    assertEq(instance.OWNER_HAT(), tophat);
  }

  function test_arbitratorHat() public {
    assertEq(instance.ARBITRATOR_HAT(), arbitratorHat);
  }

  function test_agreement() public {
    assertEq(instance.currentAgreement(), agreement);
  }

  function test_agreementId() public {
    assertEq(instance.currentAgreementId(), 1);
  }

  //function test_graceEndsAt() public {
  //  assertEq(instance.graceEndsAt(), block.timestamp + gracePeriod);
  //}
}

/*
contract SetAgreement is WithInstanceTest {
  function setUp() public virtual override {
    super.setUp();
    agreement = "this is the new agreement";
  }

  function test_happy() public {
    gracePeriod = 20 days;

    vm.expectEmit();
    emit AgreementClaimsHatter_AgreementSet(agreement, block.timestamp + gracePeriod);

    vm.prank(dao);
    instance.setAgreement(agreement, gracePeriod);

    assertEq(instance.currentAgreement(), agreement);
    assertEq(instance.currentAgreementId(), 2);
    assertEq(instance.graceEndsAt(), block.timestamp + gracePeriod);
  }

  function test_revert_notOwner() public {
    gracePeriod = 20 days;

    vm.expectRevert(AgreementClaimsHatter_NotOwner.selector);

    vm.prank(nonWearer);
    instance.setAgreement(agreement, gracePeriod);
  }

  function test_revert_shorterThanMinGrace() public {
    gracePeriod = 1 days;

    vm.expectRevert(AgreementClaimsHatter_GraceTooShort.selector);

    vm.prank(dao);
    instance.setAgreement(agreement, gracePeriod);
  }

  function test_revert_graceNotOver() public {
    gracePeriod = 8 days; // 1 day shorter than the current grace period

    vm.expectRevert(AgreementClaimsHatter_GraceNotOver.selector);

    vm.prank(dao);
    instance.setAgreement(agreement, gracePeriod);
  }
}

contract Claim is WithInstanceTest {
  function test_happy_1claimer() public {
    assertTrue(HATS.isAdminOfHat(address(instance), claimableHat), "instance not admin of claimableHat");

    vm.expectEmit();
    emit AgreementClaimsHatter_HatClaimedWithAgreement(claimer1, claimableHat, agreement);

    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    assertEq(instance.claimerAgreements(claimer1), 1);
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));
  }

  function test_happy_2claimers() public {
    // first claim
    vm.expectEmit();
    emit AgreementClaimsHatter_HatClaimedWithAgreement(claimer1, claimableHat, agreement);

    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    assertEq(instance.claimerAgreements(claimer1), 1);
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));

    // second claim
    vm.expectEmit();
    emit AgreementClaimsHatter_HatClaimedWithAgreement(claimer2, claimableHat, agreement);

    vm.prank(claimer2);
    instance.claimHatWithAgreement();

    assertEq(instance.claimerAgreements(claimer2), 1);
    assertTrue(HATS.isWearerOfHat(claimer2, claimableHat));
  }

  function test_revert_alreadyWearingHat() public {
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    assertEq(instance.claimerAgreements(claimer1), 1);
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));

    // now try again, expecting a revert
    vm.expectRevert();
    vm.prank(claimer1);
    instance.claimHatWithAgreement();
  }

  function test_revert_notEligible() public {
    // claim
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    // get revoked
    vm.prank(arbitrator);
    instance.revoke(claimer1);

    // try to claim again, expected revert because in bad standing
    vm.prank(claimer1);
    vm.expectRevert();
    instance.claimHatWithAgreement();
  }
}

contract SignAgreement is WithInstanceTest {
  function test_happy() public {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    assertEq(instance.claimerAgreements(claimer1), 1);
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));

    // new agreement is set
    string memory newAgreement = "this is the new agreement";
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // sign the new agreement
    vm.expectEmit();
    emit AgreementClaimsHatter_AgreementSigned(claimer1, newAgreement);

    vm.prank(claimer1);
    instance.signAgreement();

    assertEq(instance.claimerAgreements(claimer1), 2);
  }

  function test_revert_hatNotClaimed() public {
    vm.expectRevert(AgreementClaimsHatter_HatNotClaimed.selector);

    vm.prank(claimer1);
    instance.signAgreement();
  }

  function test_revert_alreadySigned() public {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    assertEq(instance.claimerAgreements(claimer1), 1);
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));

    // no new agreement is set

    // attempt to sign the same agreement
    vm.expectRevert(AgreementClaimsHatter_AlreadySigned.selector);

    vm.prank(claimer1);
    instance.signAgreement();
  }

  function test_afterGracePeriod() public {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    assertEq(instance.claimerAgreements(claimer1), 1);
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));

    // new agreement is set
    string memory newAgreement = "this is the new agreement";
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // warp past the grace period
    vm.warp(instance.graceEndsAt());

    // not wearing the hat any more
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));

    // sign the new agreement
    vm.expectEmit();
    emit AgreementClaimsHatter_AgreementSigned(claimer1, newAgreement);

    vm.prank(claimer1);
    instance.signAgreement();
    assertEq(instance.claimerAgreements(claimer1), 2);

    // now wearing the hat again
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));
  }
}

contract Revoke is WithInstanceTest {
  function test_happy() public {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    // revoke
    vm.prank(arbitrator);
    instance.revoke(claimer1);

    assertFalse(instance.wearerStanding(claimer1));
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));
  }

  function test_revert_notArbitrator() public {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    // attempt to revoke from non-arbitrator, expecting revert
    vm.prank(nonWearer);
    vm.expectRevert(AgreementClaimsHatter_NotArbitrator.selector);
    instance.revoke(claimer1);

    assertTrue(instance.wearerStanding(claimer1));
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));
  }
}

contract Forgive is WithInstanceTest {
  function test_happy() public {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    // revoke
    vm.prank(arbitrator);
    instance.revoke(claimer1);

    assertFalse(instance.wearerStanding(claimer1));
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));

    // forgive
    vm.prank(arbitrator);
    instance.forgive(claimer1);

    assertTrue(instance.wearerStanding(claimer1));
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));
  }

  function test_revert_notArbitrator() public {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    // revoke
    vm.prank(arbitrator);
    instance.revoke(claimer1);

    // attempt to forgive from non-arbitrator, expecting revert
    vm.prank(nonWearer);
    vm.expectRevert(AgreementClaimsHatter_NotArbitrator.selector);
    instance.forgive(claimer1);

    assertFalse(instance.wearerStanding(claimer1));
  }
}

contract WearerStatus is WithInstanceTest {
  bool public eligible;
  bool public standing;
  string newAgreement = "this is the new agreement";

  function test_claimed() public Eligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
  }

  function test_signedNew() public Eligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    // new agreement is set
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // sign the new agreement
    vm.prank(claimer1);
    instance.signAgreement();

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
  }

  function test_signedOld_inGracePeriod() public Eligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    // new agreement is set
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // don't sign the new agreement
    assertEq(instance.claimerAgreements(claimer1), 1);

    // warp to within grace period
    vm.warp(instance.graceEndsAt() - 1);

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
  }

  function test_signedOld_afterGracePeriod() public notEligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    // new agreement is set
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // don't sign the new agreement
    assertEq(instance.claimerAgreements(claimer1), 1);

    // warp to after grace period
    vm.warp(instance.graceEndsAt());

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
  }

  function test_signedPrevious_inGracePeriod() public Eligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    // new agreement is set
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // sign the new agreement
    vm.prank(claimer1);
    instance.signAgreement();
    assertEq(instance.claimerAgreements(claimer1), 2);

    // 3rd agreement is set
    vm.prank(dao);
    instance.setAgreement("this is the 3rd agreement", gracePeriod);

    // don't sign the 3rd agreement
    assertEq(instance.claimerAgreements(claimer1), 2);

    // warp to in grace period
    vm.warp(instance.graceEndsAt() - 1);

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
  }

  function test_signedNew_afterGracePeriod() public Eligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    // new agreement is set
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // sign the new agreement
    vm.prank(claimer1);
    instance.signAgreement();
    assertEq(instance.claimerAgreements(claimer1), 2);

    // warp to after grace period
    vm.warp(instance.graceEndsAt());

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
  }

  function test_revoked() public notEligible badStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.claimHatWithAgreement();

    // revoke
    vm.prank(arbitrator);
    instance.revoke(claimer1);

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
  }

  function test_notClaimed_afterGracePeriod() public notEligible goodStanding {
    // not claimed
    assertEq(instance.claimerAgreements(claimer1), 0);

    // warp to after grace period
    vm.warp(instance.graceEndsAt());

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
  }

  function test_notClaimed_inGracePeriod() public notEligible goodStanding {
    // not claimed
    assertEq(instance.claimerAgreements(claimer1), 0);

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
  }

  modifier notEligible() {
    _;
    assertFalse(eligible);
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));
  }

  modifier Eligible() {
    _;
    assertTrue(eligible);
  }

  modifier badStanding() {
    _;
    assertFalse(standing);
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));
  }

  modifier goodStanding() {
    _;
    assertTrue(standing);
  }
}
*/
