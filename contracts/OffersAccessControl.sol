pragma solidity ^0.4.24;

contract OffersAccessControl {

    // The address of the account that can replace ceo, coo, cfo, lostAndFound
    address public ceoAddress;
    // The address of the account that can adjust configuration variables and fulfill offer
    address public cooAddress;
    // The address of the CFO account that receives all the fees
    address public cfoAddress;
    // The address where funds of failed "push"es go to
    address public lostAndFoundAddress;

    // The total amount of ether in escrow owned by CFO
    uint256 public totalCFOEarnings;
    // The total amount of ether in escrow owned by lostAndFound
    uint256 public totalLostAndFoundBalance;

    /// @notice Keeps track whether the contract is frozen.
    ///  When frozen is set to be true, it cannot be set back to false again,
    ///  and all whenNotFrozen actions will be blocked.
    bool public frozen = false;

    /// @notice Access modifier for CEO-only functionality
    modifier onlyCEO() {
        require(msg.sender == ceoAddress, "only CEO is allowed to perform this operation");
        _;
    }

    /// @notice Access modifier for COO-only functionality
    modifier onlyCOO() {
        require(msg.sender == cooAddress, "only COO is allowed to perform this operation");
        _;
    }

    /// @notice Access modifier for CFO-only functionality
    modifier onlyCFO() {
        require(msg.sender == cfoAddress, "only CFO is allowed to perform this operation");
        _;
    }

    /// @notice Access modifier for LostAndFound-only functionality
    modifier onlyLostAndFound() {
        require(msg.sender == lostAndFoundAddress, "only LostAndFound is allowed to perform this operation");
        _;
    }

    /// @notice Assigns a new address to act as the CEO. Only available to the current CEO.
    /// @param _newCEO The address of the new CEO
    function setCEO(address _newCEO) external onlyCEO {
        require(_newCEO != address(0), "new CEO address cannot be the zero-account");
        ceoAddress = _newCEO;
    }

    /// @notice Assigns a new address to act as the COO. Only available to the current CEO.
    /// @param _newCOO The address of the new COO
    function setCOO(address _newCOO) external onlyCEO {
        require(_newCOO != address(0), "new COO address cannot be the zero-account");
        cooAddress = _newCOO;
    }

    /// @notice Assigns a new address to act as the CFO. Only available to the current CEO.
    /// @param _newCFO The address of the new CFO
    function setCFO(address _newCFO) external onlyCEO {
        require(_newCFO != address(0), "new CFO address cannot be the zero-account");
        cfoAddress = _newCFO;
    }

    /// @notice Assigns a new address to act as the LostAndFound account. Only available to the current CEO.
    /// @param _newLostAndFound The address of the new lostAndFound address
    function setLostAndFound(address _newLostAndFound) external onlyCEO {
        require(_newLostAndFound != address(0), "new lost and found cannot be the zero-account");
        lostAndFoundAddress = _newLostAndFound;
    }

    /// @notice CFO withdraws the CFO earnings
    function withdrawTotalCFOEarnings() external onlyCFO {
        // Obtain reference
        uint256 balance = totalCFOEarnings;
        totalCFOEarnings = 0;
        cfoAddress.transfer(balance);
    }

    /// @notice LostAndFound account withdraws all the lost and found amount
    function withdrawTotalLostAndFoundBalance() external onlyLostAndFound {
        // Obtain reference
        uint256 balance = totalLostAndFoundBalance;
        totalLostAndFoundBalance = 0;
        lostAndFoundAddress.transfer(balance);
    }

    /// @notice Modifier to allow actions only when the contract is not frozen
    modifier whenNotFrozen() {
        require(!frozen, "contract needs to not be frozen");
        _;
    }

    /// @notice Modifier to allow actions only when the contract is frozen
    modifier whenFrozen {
        require(frozen, "contract needs to be frozen");
        _;
    }

    /// @notice Called by CEO role to freeze the contract.
    ///  Only intended to be used if a serious exploit is detected.
    /// @notice This is a one-way process; there is no un-freezing.
    /// @dev A frozen contract will be frozen forever, there's no way to undo this action.
    function freeze() external onlyCEO whenNotFrozen {
        frozen = true;
    }

}
