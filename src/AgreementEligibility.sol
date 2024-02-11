// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { HatsEligibilityModule, HatsModule, IHatsEligibility } from "hats-module/HatsEligibilityModule.sol";

/*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
//////////////////////////////////////////////////////////////*/

/// @dev Thrown when the caller does not wear the `OWNER_HAT`
error AgreementClaimsHatter_NotOwner();
/// @dev Thrown when the caller does not wear the `ARBITRATOR_HAT`
error AgreementClaimsHatter_NotArbitrator();
/// @dev Thrown when the new grace period is shorter than `MIN_GRACE`
error AgreementClaimsHatter_GraceTooShort();
/// @dev Thrown when the new grace period would end prior to `graceEndsAt`
error AgreementClaimsHatter_GraceNotOver();
/// @dev Thrown when attempting to sign (w/o claiming) the current `agreement` without having already claimed the hat
error AgreementClaimsHatter_HatNotClaimed();
/// @dev Thrown when the caller has already signed the current `agreement`
error AgreementClaimsHatter_AlreadySigned();

/**
 * @title AgreementClaimsHatter
 * @author spengrah
 * @author Haberdasher Labs
 * @notice A Hats Protocol module enabling individuals to permissionlessly claim a hat by signing an agreement
 */
contract AgreementClaimsHatter is HatsEligibilityModule {
  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @dev Emitted when a user "signs" the `agreement` and claims the hat
  event AgreementClaimsHatter_HatClaimedWithAgreement(address claimer, uint256 hatId, string agreement);
  /// @dev Emitted when a user "signs" the `agreement` without claiming the hat
  event AgreementClaimsHatter_AgreementSigned(address signer, string agreement);
  /// @dev Emitted when a new `agreement` is set
  event AgreementClaimsHatter_AgreementSet(string agreement, uint256 grace);

  /*//////////////////////////////////////////////////////////////
                              CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /**
   * This contract is a clone with immutable args, which means that it is deployed with a set of
   * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
   * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
   * but requires a slightly different approach since they are read from calldata instead of storage.
   *
   * Below is a table of constants and their locations.
   *
   * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
   *
   * ------------------------------------------------------------------------+
   * CLONE IMMUTABLE "STORAGE"                                               |
   * ------------------------------------------------------------------------|
   * Offset  | Constant            | Type      | Length | Source             |
   * ------------------------------------------------------------------------|
   * 0       | IMPLEMENTATION      | address   | 20     | HatsModule         |
   * 20      | HATS                | address   | 20     | HatsModule         |
   * 40      | hatId               | uint256   | 32     | HatsModule         |
   * 72      | OWNER_HAT           | uint256   | 32     | this               |
   * 104     | ARBITRATOR_HAT      | uint256   | 32     | this               |
   * 136     | MIN_GRACE           | uint256   | 32     | this               |
   * ------------------------------------------------------------------------+
   */

  /// @notice The id of the hat whose wearer serves as the owner of this contract
  function OWNER_HAT() public pure returns (uint256) {
    return _getArgUint256(72);
  }

  /// @notice The id of the hat whose wearer serves as the arbitrator for this contract
  function ARBITRATOR_HAT() public pure returns (uint256) {
    return _getArgUint256(104);
  }

  /// @notice The minimum grace period for a new agreement
  function MIN_GRACE() public pure returns (uint256) {
    return _getArgUint256(136);
  }

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  /// @dev The current agreement, typically as a CID of the agreement plaintext
  string public currentAgreement;

  /// @notice The id of the current agreement
  /// @dev The first agreement is id 1 (see {setUp}) so that id 0 can be used in {claimerAgreements} to indicate that an
  /// address has not signed any agreements
  uint256 public currentAgreementId;

  /// @notice The timestamp at which the current grace period ends. Existing wearers of `hatId` have until this time to
  /// sign the current agreement.
  uint256 public graceEndsAt;

  /// @notice The most recent agreement that each wearer has signed
  /// @dev agreementId=0 indicates that the wearer has not signed any agreements
  mapping(address claimer => uint256 agreementId) public claimerAgreements;

  /// @dev The inverse of the standing of each wearer; inversed so that wearers are in good standing by default
  mapping(address wearer => bool badStandings) internal _badStandings;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the implementation contract and set its version
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version) HatsModule(_version) { }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsModule
  function _setUp(bytes calldata _initData) internal override {
    // decode init data
    (string memory agreement, uint256 _grace) = abi.decode(_initData, (string, uint256));

    // set the initial agreement
    currentAgreement = agreement;
    ++currentAgreementId;

    // grace period must be at least `MIN_GRACE`
    if (_grace < MIN_GRACE()) revert AgreementClaimsHatter_GraceTooShort();
    graceEndsAt = block.timestamp + _grace;
  }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Claim the `hatId` hat and sign the current agreement
   * @dev Mints the hat to the caller if they...
   *     - do already wear the hat, and
   *     - are not in bad standing for the hat.
   */
  function claimHatWithAgreement() public {
    uint256 agreementId = currentAgreementId; // save SLOADs

    // we need to set the claimer's agreement before minting so that they are eligible for the hat on minting
    claimerAgreements[msg.sender] = agreementId;

    /**
     * @dev this call will revert if msg.sender...
     *       - is currently wearing the hat, or
     *       - is in bad standing for the hat
     */
    HATS().mintHat(hatId(), msg.sender);

    emit AgreementClaimsHatter_HatClaimedWithAgreement(msg.sender, hatId(), currentAgreement);
  }

  /**
   * @notice Sign the current agreement without claiming the hat. For users who have signed a previous agreement.
   * @dev Reverts if the caller has not already claimed the hat or has already signed the current agreement.
   */
  function signAgreement() public {
    uint256 agreementId = currentAgreementId; // save SLOADs
    uint256 claimerAgreementId = claimerAgreements[msg.sender]; // save SLOADs

    if (claimerAgreementId == 0) revert AgreementClaimsHatter_HatNotClaimed();

    if (claimerAgreementId == agreementId) revert AgreementClaimsHatter_AlreadySigned();

    claimerAgreements[msg.sender] = agreementId;

    emit AgreementClaimsHatter_AgreementSigned(msg.sender, currentAgreement);
  }

  /*//////////////////////////////////////////////////////////////
                      HATS ELIGIBILITY FUNCTION
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IHatsEligibility
  function getWearerStatus(address _wearer, uint256 /* _hatId */ )
    public
    view
    override
    returns (bool eligible, bool standing)
  {
    standing = !_badStandings[_wearer];

    // bad standing means ineligible
    if (!standing) return (false, false);

    uint256 claimerAgreementId = claimerAgreements[_wearer]; // save SLOADs
    uint256 agreementId = currentAgreementId; // save SLOAD

    unchecked {
      // _wearer is eligible if they have signed the current agreement, or...
      if (claimerAgreementId == agreementId) {
        eligible = true;
        // if we are in a grace period and they have signed the previous agreement
        /// @dev agreementId is always > 0 after initialization, so this subtraction is safe
      } else if (block.timestamp < graceEndsAt && claimerAgreementId == agreementId - 1 && claimerAgreementId > 0) {
        eligible = true;
      }
    }
  }

  /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Set a new agreement, with a grace period
   * @dev Only callable by a wearer of the `OWNER_HAT`
   * @param _agreement The new agreement, as a hash of the agreement plaintext (likely a CID)
   * @param _grace The new grace period; must be at least `MIN_GRACE` seconds and end after the current grace period
   */
  function setAgreement(string calldata _agreement, uint256 _grace) public onlyOwner {
    uint256 _graceEndsAt = block.timestamp + _grace;

    if (_grace < MIN_GRACE()) revert AgreementClaimsHatter_GraceTooShort();
    // new grace period must end after the current grace period
    if (_graceEndsAt < graceEndsAt) revert AgreementClaimsHatter_GraceNotOver();

    graceEndsAt = _graceEndsAt;
    currentAgreement = _agreement;
    ++currentAgreementId;

    emit AgreementClaimsHatter_AgreementSet(_agreement, _graceEndsAt);
  }

  /**
   * @notice Revoke the `_wearer`'s hat and place them in bad standing
   * @dev Only callable by a wearer of the `ARBITRATOR_HAT`
   * @param _wearer The address of the wearer from whom to revoke the hat
   */
  function revoke(address _wearer) public onlyArbitrator {
    // set bad standing in this contract
    _badStandings[_wearer] = true;

    // revoke _wearer's hat and set their standing to false in Hats.sol
    HATS().setHatWearerStatus(hatId(), _wearer, false, false);

    /**
     * @dev Hats.sol will emit the following events:
     *   1. ERC1155.TransferSingle (burn)
     *   2. Hats.WearerStandingChanged
     */
  }

  /**
   * @notice Forgive the `_wearer`'s bad standing, allowing them to claim the hat again
   * @dev Only callable by a wearer of the `ARBITRATOR_HAT`
   * @param _wearer The address of the wearer to forgive
   */
  function forgive(address _wearer) public onlyArbitrator {
    _badStandings[_wearer] = false;

    HATS().setHatWearerStatus(hatId(), _wearer, true, true);

    /// @dev Hats.sol will emit a Hats.WearerStandingChanged event
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns whether `_wearer` is in good standing
   * @param _wearer The address to check
   */
  function wearerStanding(address _wearer) public view returns (bool) {
    return !_badStandings[_wearer];
  }

  /*//////////////////////////////////////////////////////////////
                            MODIFERS
  //////////////////////////////////////////////////////////////*/

  /// @notice Reverts if the caller is not wearing the OWNER_HAT.
  modifier onlyOwner() {
    if (!HATS().isWearerOfHat(msg.sender, OWNER_HAT())) revert AgreementClaimsHatter_NotOwner();
    _;
  }

  /// @notice Reverts if the caller is not wearing the ARBITRATOR_HAT.
  modifier onlyArbitrator() {
    if (!HATS().isWearerOfHat(msg.sender, ARBITRATOR_HAT())) revert AgreementClaimsHatter_NotArbitrator();
    _;
  }
}
