# Agreement Eligibility

The Agreement Eligibility is a [Hats Protocol](https://github.com/Hats-Protocol/hats-protocol) [module](https://github.com/Hats-Protocol/hats-module) that a community or organization can use to enable individuals to join the community by signing an agreement.

When an individual signs the agreement, they also receive a hat that grants them access to the community. If a new agreement is published, community members must sign the new agreement to continue to wear the hat and remain a member of the community.

### Deployment and Initialization

The module is deployed and initialized by the organization. As a Hats Protocol module, it can be deployed via the [Hats Module Factory](https://github.com/Hats-Protocol/hats-module#hatsmodulefactory). When the contract is deployed, the organization must specify the following parameters:

Immutable parameters:

- `hatId` — The hat id for the community hat
- `OWNER_HAT` — The hat id for the owner hat, i.e., the hat whose wearer is authorized to publish new agreements
- `ARBITRATOR_HAT` — The hat id for the arbitrator hat, i.e. the hat whose wearer is authorized to revoke the community hat from a given community member

Mutable parameters:

- `agreement` — The initial agreement, in the form of a hash. This is typically a CID pointing to a file containing the plaintext of the agreement.

### Signing the Agreement and Claiming the Community Hat (Anyone)

Anyone can make themselves eligible for the hat by signing the agreement. There are two options of doing so:
1. Signing the agreement and claiming the hat, in one transaction. Doing so involves calling the `signAgreementAndClaimHat` function. The function receives as an input a [Multi Claims Hatter](https://github.com/Hats-Protocol/multi-claims-hatter) instance, which will be used for claiming the hat.

2. Only signing the agreement, using the `signAgreement` function.

### Signing a New Agreement (Active Community Members Only)

When a new agreement is published by the organization (see below), all current wearers of the community hat — i.e., active members of the community — must sign the new agreement within a specified time period to remain a member of the community.

This specified time period is called the "grace period" and is set by the wearer of the Owner Hat when publishing the new agreement.

Active community members can sign the new agreement by calling the `signAgreement()` function, which emits an event reflecting the member's "signature" of the new agreement.

### Publishing a New Agreement (Owner Only)

The wearer of the `OWNER_HAT` can publish a new agreement by calling the `setAgreement()` function. Just like intialization, this involves passing both the `agreement` and `grace` parameters. This action also increments the `currentAgreementId`.

Once a new agreement is set, the grace period begins.

### Revoking a Community Member's Hat (Arbitrator Only)

The wearer of the `ARBITRATOR_HAT` can revoke a community member's hat by calling the `revoke()` function. This function takes a single parameter, `wearer`, which is the address of the community member whose hat is being revoked.

When a hat is revoked, the hat is burned and the member is placed in badStanding within Hats Protocol. This means that the member is no longer eligible to wear the community hat and cannot re-claim the community hat until the arbitrator places them back in good standing.

### Forgiving a Community Member (Arbitrator Only)

If an individual's community hat has been revoked, then they are in bad standing. If the wearer of the `ARBITRATOR_HAT` believes that the individual has made up for the behavior that led to the revocation, they can call the `forgive()` function. This places the individual back in good standing, enabling them to claim the community hat again if they so choose.

### Hat Eligibility

This contract also serves as an Eligibility module for the community hat. This means that it implements the `IHatsEligibility` interface, i.e. the `getWearerStatus()` function. This function returns the `eligible` and `standing` status for the given address.

These wearer statuses will differ depending on the scenario, as outlined in the table below.

| Scenario | `eligible` | `standing` |
| -------- | -------- | -------- |
| Wearer has claimed the hat and signed the current agreement | true | true |
| Wearer has claimed the hat; there is a new agreement that the wearer has not signed, but the grace period has not ended | true | true |
| Wearer has claimed the hat; there is a new agreement that the wearer has not signed, and the grace period has ended | false | true |
| Wearer has claimed the hat; there is a new agreement that the wearer has signed | true | true |
| Arbitrator has `revoke()`d the wearer's hat, placing them in bad standing | false | false |
| Arbitrator has `forgive()`n the wearer after revoking their hat, but they have have not reclaimed the hat | false | true |

## Development

This repo uses Foundry for development and testing. To get started:

1. Fork the project
2. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
3. To compile the contracts, run `forge build`
4. To test, run `forge test`
