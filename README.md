![bugbounty-07](https://user-images.githubusercontent.com/37638382/48523883-fd458280-e832-11e8-982c-c93f5d72f8bc.jpg)

# CryptoKitties Bug Bounty v2
## “Offers” Feature By Dapper Labs, Inc.

At Dapper Labs we recognize the important role security researchers play in keeping our community safe and the CryptoKittiesⓇ game enjoyable. We’re inviting members of the community to help us seek out and help resolve security vulnerabilities for an upcoming CryptoKitties smart contract via our bug bounty program described below (the “Program”).

## What you Should Know About CryptoKitties:

CryptoKitties, in which players collect and breed adorable digital Kitties that live on the Ethereum blockchain, is the world’s most popular cryptocollectible game. Launched in November 2017, the game has accounted for up to 25% of traffic on the Ethereum network at peak times. To date more than a million Kitties have been born, and players have exchanged over US $25M across more than three million smart contract transactions –– the most used contracts outside of exchanges. 

## What you Should Know About the CryptoKitties Offers Feature:

The new CryptoKitties “Offers” feature allows players to make an offer to buy any Kitty.

The feature adds one official smart contract, the Offers contract, and is supported by CryptoKitties’ core contract’s approve() function when a valid offer is accepted.

There are five parties in any successful Offers transaction: the bidder, the Kitty owner, the Offers smart contract, the CryptoKitties Core contract and the COO. In a successful Offers transaction, the bidder creates their offer, and the owner accepts it. Owners do not interact with the Offers contract, but instead call approve() on CK Core to approve the Offers contract to transfer their token. Once the offer is accepted, the COO fulfills the offer as soon as our off-chain checks pass. Only then will our worker fulfill the offer to have the token transferred to the bidder and ether offer to the owner (minus fees). If the Offers contract is not approved for that token, the fulfillment transaction will fail.

### Fulfillment criteria
- Offers contract has been approved for tokenId
- Owner’s offer accepted, so the offer response is TRUE in our db
- Kitty is not listed in an auction
- Offer has not expired

### Definitions

- Expiry - time until offer is no longer acceptable
- Offer cut - max percentage of the msg.value sent with the createOffer transaction we earn dependent on the outcome of the offer
- Unsuccessful compensation – flat fee taken in the cases when an offer has been expired/outbid
- Roles:
  - Bidder - user who creates the offer
  - Owner - owner of Kitty being offered on
  - CEO - ability to replace CEO, COO, CFO, LostAndFound
  - COO - ability to adjust configuration variables and fulfills offers
  - CFO - ability to receive fees from offer cut
  - LostAndFound – withdraws funds that have failed to be sent to other addresses


Cases | Success | Cancel | Expired / Overbidden
-- | -- | -- | --
Owner | P | 0 | 0
Bidder | 0 | T - S * P | T - flat
CFO | T - P | S * P | flat
Sum | T | T | T

### Feature design goals
- Best possible end UX for the owner
  - Prioritize owner’s experience
  - Absorb gas costs to call batchRemoveExpired and fulfillOffer 
  - Simplify transaction fees, the most we can ever take is the offer cut upon success or cancellation. In the event an offer expires or is overbid, we simply take the flat fee.

### Design and implementation decisions
- tryPushFunds - if sending funds to  an address fails for whatever reason, then the logic will continue and the amount will be kept under the LostAndFound account to ensure the transaction doesn’t fail.
- minPrice - if a higher offer is placed between the time an owner calls approve() and the time we call fulfillOffer(), the contract will always accept the current, higher offer. Also this prevents us from fulfilling an offer that is lower than what the owner has accepted.
- Configurable variables - allows us flexibility over settings to improve user experience
- fulfillOffer - owner can fulfill the offer, we also allow COO to fulfill on behalf of the owner in order to provide better UX.
- Limit liability
  - Segregated funds, we can only touch the offers cut
  - Freeze function stopping the contract with an escape hatch allowing users to withdraw their funds. There is no way to unfreeze the contract

#### Emitted events
- OfferCreated
- OfferCanceled
- OfferFulfilled
- ExpiredOfferRemoved
- OfferUpdated
- BidderWithdrewFundsWhenFrozen
- MinimumTotalValueSet
- GlobalDurationSet
- OfferCutSet
- UnsuccessfulCompensationSet
- setMinimumPriceIncrement
- PushFundsFailed

## The Scope for the Bounty Program:
This Program will run from November 14th through 18th (the “Program Period”). The offers contract is live on the Rinkeby test network at this address: `0x5495b9791f78ee081e5e894d2e46082b1ff2085e`

All code relevant to this Program is publicly available within this repo.

Please help us identify bugs, vulnerabilities, and exploits in the smart contract for this Program, such as:
- Tampering with offer mechanics for other users
- Tampering with permissions
- Gas inefficiencies

### Rules:
- Issues that have already been submitted by another user or are already known to Dapper Labs are not eligible for bounty rewards.
- Bugs and vulnerabilities should only be found using accounts you own and create. Please respect third party applications, and understand that an exploit that is not specific to the CryptoKitties Offers smart contract is not part of the Program. Attacks on the network that result in bad behaviour are not allowed.
- The CryptoKitties or Dapper Labs websites are not part of the Program, only the smart contract code included in this repo.
- Dapper Labs considers a number of variables in determining rewards. Determinations of eligibility, score and all terms related to a reward are at the sole and final discretion of Dapper Labs.
- Reports will only be accepted via GitHub issues submitted to this repo.
- In general, please investigate and report bugs in a way that makes a reasonable, good faith effort not to be disruptive or harmful to us or others.
- Don’t attempt to gain access to another user’s accounts or data.
- Don’t perform any attack that could harm the reliability/integrity of our service or data.  DDoS/spam attacks are not allowed.
- Don’t publicly disclose a bug before it has been fixed.
- Never attempt non-technical attacks such as social engineering, phishing, or physical attacks against our employees, users, or infrastructure.
- The value of rewards paid out will vary depending on Severity which is calculated based on Impact and Likelihood as followed by OWASP:

<img src="https://user-images.githubusercontent.com/37638382/48523613-0bdf6a00-e832-11e8-8769-5ecb9eb42536.png" width="400" />

Note: Rewards are at the sole discretion of Dapper Labs. 1 point currently corresponds to 1 USD (paid in ETH). Our best bug finders will receive limited edition BugCat 2.

- Critical: up to 1000 points
- High: up to 500 points
- Medium: up to 250 points
- Low: up to 125 points
- Note: up to 50 points

### Examples of Impact:
High
- Tampering with permissions or funds
- Tampering with offer mechanics for other users
- Incorrect implementation of the offers functionality / formula

Medium:
- Competitive advantage in bidding

Low:
- Gas inefficiencies
- Ambiguous code (Note)
- Better naming conventions (Note)

### Suggestions for Getting the Highest Score:
- Description: Be clear in describing the vulnerability or bug. If possible, share code scripts, screenshots, and detailed descriptions.
- Fix it: if you can suggest how we fix this issue in an appropriate manner, higher points will be rewarded.

Dapper Labs appreciates you taking the time to participate in our program, which is why we’ve created rules for us too:

- We will respond as quickly as we can to your submission (within 3 days, if we’re able).
- We’ll do our best to let you know if your submission will qualify for a bounty (or not) within 7 business days.
- We will keep you updated as we work to fix the bug you submitted.
- Our core development team, employees, and any other people paid by the CryptoKitties or Dapper Labs are not eligible for rewards.

### How to Create a Good Vulnerability Submission:
- Description: A brief description of the vulnerability.
- Scenario: A description of the requirements or circumstances for the vulnerability to happen.
- Impact: The result of the vulnerability and what or who can be affected.
- Reproduction: Provide the exact steps on how to reproduce this vulnerability on a new contract, and if possible, point to specific tx hashes or accounts used.
- Note: If we can't reproduce with given instructions then a (Truffle) test case will be required.
- Fix: If applies, what would you do to fix this

### Dapper Labs representatives:

**Judging committee:**
- @zhangchiqing (Leo)
- @hwrdtm (Howard)
- @bradleymcallister97 (Bradley)
- @flockonus (Fabiano)
- @chrisaxiom (Chris)
- @jordanschalm (Jordan)
- @dete (Dieter)

**Community & Rules:**
- @evankeast (Evan)

**Final Scores:**
- @jordankitty (Jordan)
- @arthurcamara1 (Arthur)

### FAQ:
- **How are the bounties paid out?**
  - Rewards are paid out in ETH after the submission has been validated, usually a few days later. 
- **I reported an issue but have not received a response!**
  - We aim to respond to submissions as fast as possible. Feel free to email us if you have not received a response.
- **Can I use this code elsewhere?**
  - Sure
- **I have more questions!**
  - Create a new issue with the title starting as “QUESTION”
- **Will the code change during the bounty?**
  - Yes, as issues are reported we will update the code as soon as possible. Please make sure your bugs are reported against the latest versions of the published code.

### Important Legal Information:
The Program is an experimental rewards program for our community to encourage and reward those who are helping us to improve Dapper Labs’ products. You should know that we can close the Program at any time, and rewards are at the sole discretion of the CryptoKitties team. By participating in the Program, you acknowledge that you have read and agree to the CryptoKitties Terms of Use, as well as the following: (i) you’re not participating from a country against which the United States or Canada has issued export sanctions or other trade restrictions, including, without limitation, Iran, North Korea, Sudan, or Syria; (ii) your participation in the Program will not violate any law applicable to you, or disrupt or compromise any data that is not your own; and (iii) you are solely responsible for all applicable taxes, withholding or otherwise, arising from or relating to your participation in the Program, including from any bounty payments.

Copyright (c) 2018 Dapper Labs, Inc.

All rights reserved. The contents of this repository is provided for review and educational purposes ONLY.
