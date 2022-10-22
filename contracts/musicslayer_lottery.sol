// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

// The lottery contract is not a token. We only use the IERC20 interface so that any tokens sent to this contract can be accessed.

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol"
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// Chainlink VRF contracts.

// import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
interface LinkTokenInterface {
    function allowance(address owner, address spender) external view returns (uint256 remaining);
    function approve(address spender, uint256 value) external returns (bool success);
    function balanceOf(address owner) external view returns (uint256 balance);
    function decimals() external view returns (uint8 decimalPlaces);
    function decreaseApproval(address spender, uint256 addedValue) external returns (bool success);
    function increaseApproval(address spender, uint256 subtractedValue) external;
    function name() external view returns (string memory tokenName);
    function symbol() external view returns (string memory tokenSymbol);
    function totalSupply() external view returns (uint256 totalTokensIssued);
    function transfer(address to, uint256 value) external returns (bool success);
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool success);
    function transferFrom(address from, address to, uint256 value) external returns (bool success);
}

// import "@chainlink/contracts/src/v0.8/interfaces/VRFV2WrapperInterface.sol";
interface VRFV2WrapperInterface {
    function lastRequestId() external view returns (uint256);
    function calculateRequestPrice(uint32 _callbackGasLimit) external view returns (uint256);
    function estimateRequestPrice(uint32 _callbackGasLimit, uint256 _requestGasPriceWei) external view returns (uint256);
}

// import "@chainlink/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";
abstract contract VRFV2WrapperConsumerBase {
    LinkTokenInterface internal immutable LINK;
    VRFV2WrapperInterface internal immutable VRF_V2_WRAPPER;

    constructor(address _link, address _vrfV2Wrapper) {
        LINK = LinkTokenInterface(_link);
        VRF_V2_WRAPPER = VRFV2WrapperInterface(_vrfV2Wrapper);
    }

    function requestRandomness(uint32 _callbackGasLimit, uint16 _requestConfirmations, uint32 _numWords) internal returns (uint256 requestId) {
        LINK.transferAndCall(address(VRF_V2_WRAPPER), VRF_V2_WRAPPER.calculateRequestPrice(_callbackGasLimit), abi.encode(_callbackGasLimit, _requestConfirmations, _numWords));
        return VRF_V2_WRAPPER.lastRequestId();
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal virtual;

    function rawFulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) external {
        require(msg.sender == address(VRF_V2_WRAPPER), "only VRF V2 wrapper can fulfill");
        fulfillRandomWords(_requestId, _randomWords);
    }
}

/**
 * @title The Musicslayer Lottery
 * @author Musicslayer
 */
contract MusicslayerLottery is VRFV2WrapperConsumerBase {
    /*
    *
    *
        Errors
    *
    *
    */

    /// @notice The requestId of the Chainlink VRF request does not match the requestId of the callback.
    error ChainlinkVRFRequestIdMismatch(uint callbackRequestId, uint expectedRequestId);

    /// @notice The Chainlink VRF request was initiated during a previous lottery.
    error ChainlinkVRFRequestStale(uint requestLotteryNumber, uint currentLotteryNumber);

    /// @notice This contract is corrupt.
    error CorruptContractError();

    /// @notice Drawing a winning ticket is not allowed at this time.
    error DrawWinningTicketError();

    /// @notice The current lottery is active.
    error LotteryActiveError();

    /// @notice The current lottery is not active.
    error LotteryInactiveError();

    /// @notice The lottery is not canceled.
    error LotteryNotCanceledError(uint lotteryNumber);

    /// @notice This transaction is attempting to purchase too many tickets.
    error MaxTicketPurchaseError(uint requestedTicketPurchase, uint maxTicketPurchase);

    /// @notice A winning ticket has not been drawn yet.
    error NoWinningTicketDrawnError();

    /// @notice This contract is not corrupt.
    error NotCorruptContractError();

    /// @notice The calling address is not the operator.
    error NotOperatorError(address _address, address operatorAddress);

    /// @notice The calling address is not the operator successor.
    error NotOperatorSuccessorError(address _address, address operatorSuccessorAddress);

    /// @notice The calling address is not the owner.
    error NotOwnerError(address _address, address ownerAddress);

    /// @notice The calling address is not the owner successor.
    error NotOwnerSuccessorError(address _address, address ownerSuccessorAddress);

    /// @notice The calling address is not an eligible player.
    error NotPlayerError(address _address);

    /// @notice The required penalty has not been paid.
    error PenaltyPaymentError(uint value, uint penalty);

    /// @notice The self-destruct is not ready.
    error SelfDestructNotReadyError();

    /// @notice The token contract could not be found.
    error TokenContractError(address tokenAddress);

    /// @notice The token withdraw is not allowed.
    error TokenWithdrawError(address tokenAddress, uint requestedValue, uint tokenBalance, uint tokenMinimumReserve);

    /// @notice The token transfer failed.
    error TokenTransferError(address tokenAddress, address _address, uint requestedValue);

    /// @notice A winning ticket has already been drawn.
    error WinningTicketDrawnError();

    /// @notice The withdraw is not allowed.
    error WithdrawError(uint requestedValue, uint operatorContractBalance);
    
    /*
    *
    *
        Events
    *
    *
    */

    /// @notice A record of the contract becoming corrupt.
    event Corruption(uint indexed blockNumber);

    /// @notice A record of the contract becoming uncorrupt.
    event CorruptionReset(uint indexed blockNumber);

    /// @notice A record of a lottery being canceled.
    event LotteryCancel(uint indexed lotteryNumber, uint indexed lotteryBlockNumberStart);

    /// @notice A record of a lottery ending.
    event LotteryEnd(uint indexed lotteryNumber, uint indexed lotteryBlockNumberStart, address indexed winnerAddress, uint winnerPrize);

    /// @notice A record of a lottery starting.
    event LotteryStart(uint indexed lotteryNumber, uint indexed lotteryBlockNumberStart, uint indexed lotteryActiveBlocks, uint ticketPrice);

    /// @notice A record of the operator address changing.
    event OperatorChanged(address indexed oldOperatorAddress, address indexed newOperatorAddress);

    /// @notice A record of the owner address changing.
    event OwnerChanged(address indexed oldOwnerAddress, address indexed newOwnerAddress);

    /// @notice A record of the contract failing a validation check.
    event ValidationFailed(uint checkNumber);

    /// @notice A record of a winning ticket being drawn.
    event WinningTicketDrawn(uint indexed winningTicket, uint indexed totalTickets);

    /*
    *
    *
        Constants
    *
    *
    */

    /*
        Contract Constants
    */

    // The identifier of the chain that this contract is meant to be deployed on.
    uint private constant CHAIN_ID = 97; // BSC Testnet

    /*
        Lottery Constants
    */

    // The grace period after the contract becomes corrupt that everyone has to withdraw their funds before the owner can destroy it.
    uint private constant CORRUPT_CONTRACT_GRACE_PERIOD_BLOCKS = 864_000; // About 30 days.

    // This is the maximum number of tickets that can be purchased in a single transaction.
    // Note that players can use additional transactions to purchase more tickets.
    uint private constant MAX_TICKET_PURCHASE = 10_000;
    
    // An integer between 0 and 100 representing the percentage of the "playerPrizePool" amount that the operator takes every game.
    // Note that the winner always receives the entire "bonusPrizePool" amount.
    uint private constant OPERATOR_CUT = 10;

    /*
        Chainlink Constants
    */

    address private constant CHAINLINK_TOKEN_ADDRESS = 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06;
    address private constant CHAINLINK_WRAPPER_ADDRESS = 0x699d428ee890d55D56d5FC6e26290f3247A762bd;

    uint32 private constant CHAINLINK_CALLBACK_GAS_LIMIT = 200_000; // This was chosen experimentally.
    uint private constant CHAINLINK_MINIMUM_RESERVE = 40 * 10 ** CHAINLINK_TOKEN_DECIMALS; // 40 LINK
    uint16 private constant CHAINLINK_REQUEST_CONFIRMATION_BLOCKS = 200; // About 10 minutes. Use the maximum allowed value of 200 blocks to be extra secure.
    uint16 private constant CHAINLINK_REQUEST_RETRY_BLOCKS = 600; // About 30 minutes.
    uint private constant CHAINLINK_RETRY_MAX = 10;
    uint private constant CHAINLINK_TOKEN_DECIMALS = 18;
    
    /*
    *
    *
        Private Variables
    *
    *
    */

    /*
        Contract Variables
    */

    address private operatorAddress;
    address private operatorSuccessorAddress;
    address private ownerAddress;
    address private ownerSuccessorAddress;

    bool private corruptContractFlag;
    bool private lockFlag;

    uint private corruptContractBlockNumber;

    /*
        Fund Variables
    */

    /*
        To ensure the safety of player funds, the contract balance is accounted for by splitting it into different places:
          bonusPrizePool - The funds that have optionally been added to "sweeten the pot" and provide a bigger prize. The operator can add funds but cannot withdraw them.
          claimableBalancePool - The funds that have not yet been claimed. The operator takes their cut from here, but otherwise they cannot add or withdraw funds.
          contractFunds - The general funds owned by the contract. The operator can add or withdraw funds at will.
          playerPrizePool - The funds players have paid to purchase tickets. The operator cannot add or withdraw funds.
          refundPool - The funds that were in the playerPrizePool for a lottery that was canceled. Players can manually request refunds for any tickets they have purchased.
        Anything else not accounted for is considered to be "extra" funds that are treated the same as contract funds.
        Also note that tokens are not included in this accounting.
    */
    uint private bonusPrizePool;
    uint private claimableBalancePool;
    uint private contractFunds;
    uint private playerPrizePool;
    uint private refundPool;

    /*
        Lottery Variables
    */

    bool private winningTicketFlag;

    uint private currentTicketNumber;
    uint private lotteryActiveBlocks;
    uint private lotteryBlockNumberStart;
    uint private lotteryNumber;
    uint private nextLotteryActiveBlocks;
    uint private nextTicketPrice;
    uint private ticketPrice;
    uint private winningTicket;

    mapping(address => uint) private map_address2ClaimableBalance;
    mapping(uint => address) private map_ticket2Address;
    mapping(uint => address) private map_lotteryNum2WinnerAddress;
    mapping(uint => bool) private map_lotteryNum2IsCanceled;
    mapping(uint => uint) private map_lotteryNum2TicketPrice;
    mapping(uint => uint) private map_lotteryNum2WinnerPrize;
    mapping(uint => mapping(address => uint)) private map_lotteryNum2Address2NumTickets;

    /*
        Chainlink Variables
    */

    bool private chainlinkRequestIdFlag;
    
    uint private chainlinkRequestId;
    uint private chainlinkRequestIdBlockNumber;
    uint private chainlinkRetryCounter;

    mapping(uint => uint) private map_chainlinkRequestId2LotteryNum;

    /*
    *
    *
        Contract Functions
    *
    *
    */

    /*
        Built-In Functions
    */

    constructor(uint initialLotteryActiveBlocks, uint initialTicketPrice) VRFV2WrapperConsumerBase(CHAINLINK_TOKEN_ADDRESS, CHAINLINK_WRAPPER_ADDRESS) payable {
        assert(block.chainid == CHAIN_ID);

        addContractFunds(msg.value);

        setOwnerAddress(msg.sender);
        setOwnerSuccessorAddress(msg.sender);
        setOperatorAddress(msg.sender);
        setOperatorSuccessorAddress(msg.sender);

        setLotteryActiveBlocks(initialLotteryActiveBlocks);
        setTicketPrice(initialTicketPrice);

        startNewLottery();
    }

    fallback() external payable {
        // There is no legitimate reason for this fallback function to be called.
        punish();
    }

    receive() external payable {
        // Funds received from a player will be used to buy tickets. Funds received from the operator will be counted as contract funds.
        lock();

        if(isOperatorAddress(msg.sender)) {
            addContractFunds(msg.value);
        }
        else {
            requireLotteryActive();
            requireNotCorruptContract();

            buyTickets(msg.sender, msg.value);
        }

        unlock();
    }

    /*
        Action Functions
    */

    function buyTickets(address _address, uint value) private {
        // Purchase as many tickets as possible for the address with the provided value. Note that tickets can only be purchased in whole number quantities.
        // After spending all the funds on tickets, anything left over will be added to the address's claimable balance.
        uint numTickets = value / ticketPrice;
        if(numTickets > MAX_TICKET_PURCHASE) {
            revert MaxTicketPurchaseError(numTickets, MAX_TICKET_PURCHASE);
        }

        uint totalTicketValue = numTickets * ticketPrice;
        uint unspentValue = value - totalTicketValue;

        addPlayerPrizePool(totalTicketValue);
        addAddressClaimableBalance(_address, unspentValue);

        map_lotteryNum2Address2NumTickets[lotteryNumber][_address] += numTickets;
        
        // To save gas, only write the information for the first purchased ticket, and then every 100 afterwards.
        uint endTicketNumber = currentTicketNumber + numTickets;
        for(uint i = currentTicketNumber; i < endTicketNumber; i += 100) {
            map_ticket2Address[i] = _address;
        }

        currentTicketNumber = endTicketNumber;
    }

    function cancelCurrentLottery(uint value) private {
        // Mark the current lottery as refundable and start a new lottery.
        // For recordkeeping purposes, the winner is the zero address and the prize is zero.
        map_lotteryNum2IsCanceled[lotteryNumber] = true;

        // Move funds in the player prize pool to the refund pool. Players who have purchased tickets may request a refund manually.
        addRefundPool(playerPrizePool);
        subtractPlayerPrizePool(playerPrizePool);

        // Carry over the existing bonus prize pool and add in the additional value.
        addBonusPrizePool(value);

        emit LotteryCancel(lotteryNumber, lotteryBlockNumberStart);

        startNewLottery();
    }

    function claimOperatorRole(address _address) private {
        setOperatorAddress(_address);
    }

    function claimOwnerRole(address _address) private {
        setOwnerAddress(_address);
    }

    function drawWinningTicket() private {
        if(winningTicketFlag || (chainlinkRequestIdFlag && !isRetryPermitted())) {
            revert DrawWinningTicketError();
        }

        // At a certain point we must conclude that Chainlink is down and give up. Don't allow for additional attempts because they cost Chainlink tokens.
        if(chainlinkRetryCounter > CHAINLINK_RETRY_MAX) {
            setCorruptContract(true);
            return;
        }

        if(isZeroPlayerGame() || isOnePlayerGame()) {
            // Don't bother paying Chainlink for a random number.
            recordWinningTicket(0);
        }
        else {
            chainlinkRetryCounter++;
            chainlinkRequestIdFlag = true;
            chainlinkRequestIdBlockNumber = block.number;
            chainlinkRequestId = requestRandomness(CHAINLINK_CALLBACK_GAS_LIMIT, CHAINLINK_REQUEST_CONFIRMATION_BLOCKS, 1);

            map_chainlinkRequestId2LotteryNum[chainlinkRequestId] = lotteryNumber;
        }
    }

    function endCurrentLottery() private {
        // End the current lottery, credit any prizes rewarded, and then start a new lottery.
        address winnerAddress;
        uint operatorPrize;
        uint winnerPrize;

        if(isZeroPlayerGame()) {
            // No one played. For recordkeeping purposes, the winner is the zero address and the prize is zero.
            winnerAddress = address(0);
            operatorPrize = 0;
            winnerPrize = 0;
        }
        else if(isOnePlayerGame()) {
            // Since only one person has played, just give them the entire prize.
            winnerAddress = map_ticket2Address[0];
            operatorPrize = 0;
            winnerPrize = bonusPrizePool + playerPrizePool;
        }
        else {
            // Give the lottery operator their cut of the pot, and then give the rest to the randomly chosen winner.
            winnerAddress = findWinnerAddress(winningTicket);
            operatorPrize = playerPrizePool * OPERATOR_CUT / 100;
            winnerPrize = playerPrizePool + bonusPrizePool - operatorPrize;
        }

        addAddressClaimableBalance(getOperatorAddress(), operatorPrize);
        addAddressClaimableBalance(winnerAddress, winnerPrize);

        subtractPlayerPrizePool(playerPrizePool);
        subtractBonusPrizePool(bonusPrizePool);

        map_lotteryNum2WinnerAddress[lotteryNumber] = winnerAddress;
        map_lotteryNum2WinnerPrize[lotteryNumber] = winnerPrize;

        emit LotteryEnd(lotteryNumber, lotteryBlockNumberStart, winnerAddress, winnerPrize);

        startNewLottery();
    }

    function offerOperatorRole(address _address) private {
        setOperatorSuccessorAddress(_address);
    }

    function offerOwnerRole(address _address) private {
        setOwnerSuccessorAddress(_address);
    }

    /*
        Helper Functions
    */

    function findWinnerAddress(uint ticket) private view returns (address) {
        address winnerAddress = map_ticket2Address[ticket];

        // Because "map_ticket2Address" potentially has gaps, we may have to search until we find the winner address.
        // Note that because of the way "map_ticket2Address" is filled in, element 0 is guaranteed to have a nonzero address.
        while(winnerAddress == address(0)) {
            winnerAddress = map_ticket2Address[--ticket];
        }

        return winnerAddress;
    }

    // This function must be "internal" to match the abstract superclass definition.
    function fulfillRandomWords(uint requestId, uint[] memory randomWords) internal override {
        // This is the Chainlink VRF callback that will give us the random number we requested.
        if(chainlinkRequestId != requestId) {
            revert ChainlinkVRFRequestIdMismatch(requestId, chainlinkRequestId);
        }

        if(map_chainlinkRequestId2LotteryNum[requestId] != lotteryNumber) {
            revert ChainlinkVRFRequestStale(map_chainlinkRequestId2LotteryNum[requestId], lotteryNumber);
        }

        // This function will not be called if the total number of tickets is zero.
        recordWinningTicket(randomWords[0] % getTotalTickets());
    }

    function recordWinningTicket(uint _winningTicket) private {
        winningTicketFlag = true;
        winningTicket = _winningTicket;
        emit WinningTicketDrawn(_winningTicket, getTotalTickets());
    }

    function startNewLottery() private {
        // Reset lottery state and begin a new lottery. The contract is designed so that we don't need to clear any of the mappings, something that saves a lot of gas.
        currentTicketNumber = 0;

        // If any of these values have been changed by the operator, update them now before starting the next lottery.
        updateLotteryActiveBlocks();
        updateTicketPrice();

        lotteryNumber++;
        lotteryBlockNumberStart = block.number;
        winningTicketFlag = false;

        chainlinkRetryCounter = 0;
        chainlinkRequestIdFlag = false;

        map_lotteryNum2TicketPrice[lotteryNumber] = ticketPrice;

        emit LotteryStart(lotteryNumber, lotteryBlockNumberStart, lotteryActiveBlocks, ticketPrice);
    }

    function updateLotteryActiveBlocks() private {
        lotteryActiveBlocks = nextLotteryActiveBlocks;
    }

    function updateTicketPrice() private {
        ticketPrice = nextTicketPrice;
    }

    /*
        Add Functions
    */

    function addAddressClaimableBalance(address _address, uint value) private {
        map_address2ClaimableBalance[_address] += value;
        claimableBalancePool += value;
    }

    function addBonusPrizePool(uint value) private {
        bonusPrizePool += value;
    }

    function addContractFunds(uint value) private {
        contractFunds += value;
    }

    function addPlayerPrizePool(uint value) private {
        playerPrizePool += value;
    }

    function addRefundPool(uint value) private {
        refundPool += value;
    }

    /*
        Subtract Functions
    */

    function subtractAddressClaimableBalance(address _address, uint value) private {
        map_address2ClaimableBalance[_address] -= value;
        claimableBalancePool -= value;
    }

    function subtractBonusPrizePool(uint value) private {
        bonusPrizePool -= value;
    }

    function subtractContractFunds(uint value) private {
        contractFunds -= value;
    }

    function subtractPlayerPrizePool(uint value) private {
        playerPrizePool -= value;
    }

    function subtractRefundPool(uint value) private {
        refundPool -= value;
    }

    /*
        Withdraw Functions
    */

    function withdrawAddressClaimableBalance(address _address) private {
        // We only allow the entire balance to be withdrawn.
        uint balance = getAddressClaimableBalance(_address);
        subtractAddressClaimableBalance(_address, balance);
        transferToAddress(_address, balance);
    }

    function withdrawAddressRefund(uint _lotteryNumber, address _address) private {
        // We only allow the entire balance to be withdrawn.
        uint balance = getAddressRefund(_lotteryNumber, _address);
        subtractRefundPool(balance);

        map_lotteryNum2Address2NumTickets[_lotteryNumber][_address] = 0;
        
        transferToAddress(_address, balance);
    }

    function withdrawAllChainlinkBalance(address _address) private {
        tokenTransferToAddress(CHAINLINK_TOKEN_ADDRESS, _address, getTokenBalance(CHAINLINK_TOKEN_ADDRESS));
    }

    function withdrawAllContractFunds(address _address) private {
        // Withdraw the entire contract funds. For the purposes of this function, extra funds are treated as contract funds.
        uint operatorContractBalance = getOperatorContractBalance();
        subtractContractFunds(operatorContractBalance);
        transferToAddress(_address, operatorContractBalance);
    }

    function withdrawAllTokenBalance(address tokenAddress, address _address) private {
        tokenTransferToAddress(tokenAddress, _address, getTokenBalance(tokenAddress));
    }

    function withdrawChainlinkBalance(address _address, uint value) private {
        tokenTransferToAddress(CHAINLINK_TOKEN_ADDRESS, _address, value);
    }

    function withdrawContractFunds(address _address, uint value) private {
        // Withdraw an amount from the contract funds. For the purposes of this function, extra funds are treated as contract funds.
        uint extraContractBalance = getExtraContractBalance();
        if(value > extraContractBalance) {
            // Only if the value is higher than the extra funds do we subtract from "contractFunds". This accounting makes it so extra funds are spent first.
            subtractContractFunds(value - extraContractBalance);
        }
        transferToAddress(_address, value);
    }

    function withdrawTokenBalance(address tokenAddress, address _address, uint value) private {
        tokenTransferToAddress(tokenAddress, _address, value);
    }

    /*
        Query Functions
    */

    function isAddressPlaying(address _address) private view returns (bool) {
        return map_lotteryNum2Address2NumTickets[lotteryNumber][_address] != 0;
    }

    function isCorruptContract() private view returns (bool) {
        return corruptContractFlag;
    }

    function isCorruptContractGracePeriod() private view returns (bool) {
        return getRemainingCorruptContractGracePeriodBlocks() != 0;
    }

    function isLocked() private view returns (bool) {
        return lockFlag;
    }

    function isLotteryActive() private view returns (bool) {
        return getRemainingLotteryActiveBlocks() != 0;
    }

    function isLotteryCanceled(uint _lotteryNumber) private view returns (bool) {
        return map_lotteryNum2IsCanceled[_lotteryNumber];
    }

    function isOnePlayerGame() private view returns (bool) {
        // Check to see if there is only one player who has purchased all the tickets.
        return currentTicketNumber != 0 && (getAddressTickets(map_ticket2Address[0]) == getTotalTickets());
    }

    function isOperatorAddress(address _address) private view returns (bool) {
        return _address == getOperatorAddress();
    }

    function isOperatorSuccessorAddress(address _address) private view returns (bool) {
        return _address == getOperatorSuccessorAddress();
    }

    function isOwnerAddress(address _address) private view returns (bool) {
        return _address == getOwnerAddress();
    }

    function isOwnerSuccessorAddress(address _address) private view returns (bool) {
        return _address == getOwnerSuccessorAddress();
    }

    function isPenaltyPayment(uint value) private view returns (bool) {
        // We require the penalty payment to be exact so that we don't have to handle the accounting of any excess amount.
        return value == getPenaltyPayment();
    }

    function isPlayerAddress(address _address) private view returns (bool) {
        // The only ineligible player is the operator.
        return _address != getOperatorAddress();
    }

    function isRetryPermitted() private view returns (bool) {
        // We allow for a redraw if the random number has not been received after a certain number of blocks. This would be needed if Chainlink ever experiences an outage.
        return block.number - chainlinkRequestIdBlockNumber > CHAINLINK_REQUEST_RETRY_BLOCKS;
    }

    function isSelfDestructReady() private view returns (bool) {
        /*
            If this function returns true, the owner is allowed to call "selfdestruct" and withdraw the entire contract balance.
            To ensure the owner cannot just run away with prize funds, we require all of the following to be true:
              The contract must be corrupt.
              After the contract became corrupt, the owner must wait for a grace period to pass. This gives everyone a chance to withdraw any funds owed to them.
        */
        return isCorruptContract() && !isCorruptContractGracePeriod();
    }

    function isTokenWithdrawAllowed(address tokenAddress, uint value) private view returns (bool) {
        return value <= getAllowedTokenWithdrawBalance(tokenAddress);
    }

    function isWinningTicketDrawn() private view returns (bool) {
        return winningTicketFlag;
    }

    function isWithdrawAllowed(uint value) private view returns (bool) {
        return value <= getOperatorContractBalance();
    }

    function isZeroPlayerGame() private view returns (bool) {
        // If no tickets were purchased, then there cannot be any players.
        return currentTicketNumber == 0;
    }

    /*
        Require Functions
    */

    function requireCorruptContract() private view {
        if(!isCorruptContract()) {
            revert NotCorruptContractError();
        }
    }

    function requireLotteryCanceled(uint _lotteryNumber) private view {
        if(!isLotteryCanceled(_lotteryNumber)) {
            revert LotteryNotCanceledError(_lotteryNumber);
        }
    }

    function requireLotteryActive() private view {
        if(!isLotteryActive()) {
            revert LotteryInactiveError();
        }
    }

    function requireLotteryInactive() private view {
        if(isLotteryActive()) {
            revert LotteryActiveError();
        }
    }

    function requireNoWinningTicketDrawn() private view {
        if(isWinningTicketDrawn()) {
            revert WinningTicketDrawnError();
        }
    }

    function requireNotCorruptContract() private view {
        if(isCorruptContract()) {
            revert CorruptContractError();
        }
    }

    function requireOperatorAddress(address _address) private view {
        if(!isOperatorAddress(_address)) {
            revert NotOperatorError(_address, getOperatorAddress());
        }
    }

    function requireOperatorSuccessorAddress(address _address) private view {
        if(!isOperatorSuccessorAddress(_address)) {
            revert NotOperatorSuccessorError(_address, getOperatorSuccessorAddress());
        }
    }

    function requireOwnerAddress(address _address) private view {
        if(!isOwnerAddress(_address)) {
            revert NotOwnerError(_address, getOwnerAddress());
        }
    }

    function requireOwnerSuccessorAddress(address _address) private view {
        if(!isOwnerSuccessorAddress(_address)) {
            revert NotOwnerSuccessorError(_address, getOwnerSuccessorAddress());
        }
    }

    function requirePenaltyPayment(uint value) private view {
        if(!isPenaltyPayment(value)) {
            revert PenaltyPaymentError(value, getPenaltyPayment());
        }
    }

    function requirePlayerAddress(address _address) private view {
        if(!isPlayerAddress(_address)) {
            revert NotPlayerError(_address);
        }
    }

    function requireSelfDestructReady() private view {
        if(!isSelfDestructReady()) {
            revert SelfDestructNotReadyError();
        }
    }

    function requireTokenWithdrawAllowed(address tokenAddress, uint value) private view {
        if(!isTokenWithdrawAllowed(tokenAddress, value)) {
            revert TokenWithdrawError(tokenAddress, value, getTokenBalance(tokenAddress), getTokenMinimumReserve(tokenAddress));
        }
    }

    function requireWinningTicketDrawn() private view {
        if(!isWinningTicketDrawn()) {
            revert NoWinningTicketDrawnError();
        }
    }

    function requireWithdrawAllowed(uint value) private view {
        if(!isWithdrawAllowed(value)) {
            revert WithdrawError(value, getOperatorContractBalance());
        }
    }

    /*
        Get Functions
    */

    function getAccountedContractBalance() private view returns (uint) {
        return bonusPrizePool + claimableBalancePool + contractFunds + playerPrizePool + refundPool;
    }

    function getAddressClaimableBalance(address _address) private view returns (uint) {
        return map_address2ClaimableBalance[_address];
    }

    function getAddressRefund(uint _lotteryNumber, address _address) private view returns (uint) {
        return map_lotteryNum2Address2NumTickets[_lotteryNumber][_address] * map_lotteryNum2TicketPrice[_lotteryNumber];
    }

    function getAddressTickets(address _address) private view returns (uint) {
        return map_lotteryNum2Address2NumTickets[lotteryNumber][_address];
    }

    function getAddressWinChanceOutOf(address _address, uint N) private view returns (uint) {
        return getAddressTickets(_address) * N / getTotalTickets();
    }

    function getAllowedTokenWithdrawBalance(address tokenAddress) private view returns (uint) {
        // Note that aside from maintaining any minimum reserve requirements, we also forbid withdrawing an amount higher than the available balance.
        // Even if the token's contract would allow for such a strange withdraw, we do not permit it here.
        uint tokenBalance = getTokenBalance(tokenAddress);
        uint reserve = getTokenMinimumReserve(tokenAddress);

        if(tokenBalance < reserve) {
            return 0;
        }
        else {
            return tokenBalance - reserve;
        }
    }

    function getBonusPrizePool() private view returns (uint) {
        return bonusPrizePool;
    }

    function getClaimableBalancePool() private view returns (uint) {
        return claimableBalancePool;
    }

    function getContractBalance() private view returns (uint) {
        // This is the true and complete contract balance.
        return address(this).balance;
    }

    function getContractFunds() private view returns (uint) {
        return contractFunds;
    }

    function getExtraContractBalance() private view returns (uint) {
        // Returns the amount of "extra" funds this contract has. This should usually be zero, but may be more if funds are sent here in ways that cannot be accounted for.
        // For example, a coinbase transaction or another contract calling "selfdestruct" could send funds here while bypassing any accounting.
        return getContractBalance() - getAccountedContractBalance();
    }

    function getLotteryActiveBlocks() private view returns (uint) {
        return lotteryActiveBlocks;
    }

    function getLotteryBlockNumberStart() private view returns (uint) {
        return lotteryBlockNumberStart;
    }

    function getLotteryNumber() private view returns (uint) {
        return lotteryNumber;
    }

    function getLotteryTicketPrice(uint _lotteryNumber) private view returns (uint) {
        return map_lotteryNum2TicketPrice[_lotteryNumber];
    }

    function getLotteryWinnerAddress(uint _lotteryNumber) private view returns (address) {
        return map_lotteryNum2WinnerAddress[_lotteryNumber];
    }

    function getLotteryWinnerPrize(uint _lotteryNumber) private view returns (uint) {
        return map_lotteryNum2WinnerPrize[_lotteryNumber];
    }

    function getOperatorAddress() private view returns (address) {
        return operatorAddress;
    }

    function getOperatorSuccessorAddress() private view returns (address) {
        return operatorSuccessorAddress;
    }

    function getOperatorContractBalance() private view returns (uint) {
        return contractFunds + getExtraContractBalance();
    }

    function getOwnerAddress() private view returns (address) {
        return ownerAddress;
    }

    function getOwnerSuccessorAddress() private view returns (address) {
        return ownerSuccessorAddress;
    }

    function getPenaltyPayment() private view returns (uint) {
        // The base penalty is 0.1 of the native coin, but if the lottery is inactive and there are at least two players, then the penalty is multiplied by 5.
        uint penalty = 0.1 ether;
        if(!isLotteryActive() && !isZeroPlayerGame() && !isOnePlayerGame()) {
            penalty *= 5;
        }
        return penalty;
    }

    function getPlayerPrizePool() private view returns (uint) {
        return playerPrizePool;
    }

    function getRefundPool() private view returns (uint) {
        return refundPool;
    }

    function getRemainingCorruptContractGracePeriodBlocks() private view returns (uint) {
        uint numBlocksPassed = block.number - corruptContractBlockNumber;
        if(numBlocksPassed <= CORRUPT_CONTRACT_GRACE_PERIOD_BLOCKS) {
            return CORRUPT_CONTRACT_GRACE_PERIOD_BLOCKS - numBlocksPassed;
        }
        else {
            return 0;
        }
    }

    function getRemainingLotteryActiveBlocks() private view returns (uint) {
        uint numBlocksPassed = block.number - lotteryBlockNumberStart;

        if(numBlocksPassed <= lotteryActiveBlocks) {
            return lotteryActiveBlocks - numBlocksPassed;
        }
        else {
            return 0;
        }
    }

    function getTicketPrice() private view returns (uint) {
        return ticketPrice;
    }

    function getTokenBalance(address tokenAddress) private view returns (uint) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function getTokenMinimumReserve(address tokenAddress) private view returns (uint) {
        // Chainlink is the only token with a minimum reserve requirement, and if the contract is ready to be destroyed then the reserve no longer applies.
        if(tokenAddress == CHAINLINK_TOKEN_ADDRESS && !isSelfDestructReady()) {
            return CHAINLINK_MINIMUM_RESERVE;
        }
        else {
            return 0;
        }
    }

    function getTotalTickets() private view returns (uint) {
        return currentTicketNumber;
    }

    /*
        Set Functions
    */

    function setCorruptContract(bool _isCorruptContract) private {
        if(_isCorruptContract != corruptContractFlag) {
            corruptContractFlag = _isCorruptContract;

            if(_isCorruptContract) {
                corruptContractBlockNumber = block.number;
                emit Corruption(block.number);
            }
            else {
                corruptContractBlockNumber = 0;
                emit CorruptionReset(block.number);
            }
        }
    }

    function setLocked(bool _isLocked) private {
        lockFlag = _isLocked;
    }

    function setLotteryActiveBlocks(uint _nextLotteryActiveBlocks) private {
        // Do not set the current active lottery blocks here. When the next lottery starts, the current active lottery blocks will be updated.
        nextLotteryActiveBlocks = _nextLotteryActiveBlocks;
    }

    function setOperatorAddress(address _address) private {
        if(_address != operatorAddress) {
            emit OperatorChanged(operatorAddress, _address);
            operatorAddress = _address;
        }
    }

    function setOperatorSuccessorAddress(address _address) private {
        operatorSuccessorAddress = _address;
    }
    
    function setOwnerAddress(address _address) private {
        if(_address != ownerAddress) {
            emit OwnerChanged(ownerAddress, _address);
            ownerAddress = _address;
        }
    }

    function setOwnerSuccessorAddress(address _address) private {
        ownerSuccessorAddress = _address;
    }

    function setTicketPrice(uint _nextTicketPrice) private {
        // Do not set the current ticket price here. When the next lottery starts, the current ticket price will be updated.
        nextTicketPrice = _nextTicketPrice;
    }

    /*
        Reentrancy Functions
    */

    function lock() private {
        // Call this at the start of each external function that can change state to protect against reentrancy.
        if(isLocked()) {
            punish();
        }
        setLocked(true);
    }

    function unlock() private {
        // Call this at the end of each external function.
        setLocked(false);
    }

    /*
        Utility Functions
    */

    function punish() private pure {
        // This operation will cause a revert but also consume all the gas. This will punish those who are trying to attack the contract.
        assembly("memory-safe") { invalid() }
    }

    function selfDestruct(address _address) private {
        // Destroy this contract and give any native coin balance to the address. Tokens must be dealt with separately before calling this function.
        selfdestruct(payable(_address));
    }

    function tokenTransferToAddress(address tokenAddress, address _address, uint value) private {
        // Take extra care to account for tokens that don't revert on failure or that don't return a value.
        // A return value is optional, but if it is present then it must be true.
        if(tokenAddress.code.length == 0) {
            revert TokenContractError(tokenAddress);
        }

        bytes memory callData = abi.encodeWithSelector(IERC20(tokenAddress).transfer.selector, _address, value);
        (bool success, bytes memory returnData) = tokenAddress.call(callData);

        if(!success || (returnData.length != 0 && !abi.decode(returnData, (bool)))) {
            revert TokenTransferError(tokenAddress, _address, value);
        }
    }

    function transferToAddress(address _address, uint value) private {
        payable(_address).transfer(value);
    }

    /*
        Validation Functions
    */

    function validate() private {
        if(block.chainid != CHAIN_ID) {
            setCorruptContract(true);
            emit ValidationFailed(1);
            return;
        }

        if(lockFlag) {
            setCorruptContract(true);
            emit ValidationFailed(2);
            return;
        }

        if(getAccountedContractBalance() > getContractBalance()) {
            setCorruptContract(true);
            emit ValidationFailed(3);
            return;
        }

        if(getTotalTickets() * ticketPrice != playerPrizePool) {
            setCorruptContract(true);
            emit ValidationFailed(4);
            return;
        }

        if(currentTicketNumber != 0 && map_ticket2Address[0] == address(0)) {
            setCorruptContract(true);
            emit ValidationFailed(5);
            return;
        }
    }

    /*
    *
    *
        External Functions
    *
    *
    */

    /*
        Action Functions
    */

    /// @notice Players can call this to buy tickets for the current lottery, but only if it is still active and the contract is not corrupt.
    function action_buyTickets() external payable {
        lock();

        requireLotteryActive();
        requireNotCorruptContract();
        requirePlayerAddress(msg.sender);

        buyTickets(msg.sender, msg.value);

        unlock();
    }

    /// @notice The operator can call this before a winning ticket is drawn to cancel the current lottery and refund everyone. The operator gives up their cut and must pay a penalty fee to do this.
    function action_cancelCurrentLottery() external payable {
        lock();

        requireOperatorAddress(msg.sender);
        requireNoWinningTicketDrawn();
        requirePenaltyPayment(msg.value);
        
        cancelCurrentLottery(msg.value);

        unlock();
    }

    /// @notice Anyone can call this before a winning ticket is drawn to cancel the current lottery and refund everyone, but only if the contract is corrupt. There is no penalty fee in this case.
    function action_cancelCurrentLotteryCorrupt() external {
        lock();

        requireNoWinningTicketDrawn();
        requireCorruptContract();
        
        cancelCurrentLottery(0);

        unlock();
    }

    /// @notice The operator successor can claim the operator role.
    function action_claimOperatorRole() external {
        lock();

        requireOperatorSuccessorAddress(msg.sender);

        claimOperatorRole(msg.sender);

        unlock();
    }

    /// @notice The owner successor can claim the owner role.
    function action_claimOwnerRole() external {
        lock();

        requireOwnerSuccessorAddress(msg.sender);

        claimOwnerRole(msg.sender);

        unlock();
    }

    /// @notice Anyone can call this to draw the winning ticket, but only if the current lottery is no longer active.
    function action_drawWinningTicket() external {
        lock();

        requireLotteryInactive();

        drawWinningTicket();

        unlock();
    }

    /// @notice Anyone can call this to end the current lottery, but only if a winning ticket has been drawn.
    function action_endCurrentLottery() external {
        lock();

        requireWinningTicketDrawn();

        endCurrentLottery();

        unlock();
    }

    /// @notice The operator can offer the operator role to a successor address.
    /// @param _address The operator successor address.
    function action_offerOperatorRole(address _address) external {
        lock();

        requireOperatorAddress(msg.sender);

        offerOperatorRole(_address);

        unlock();
    }

    /// @notice The owner can offer the owner role to a successor address.
    /// @param _address The owner successor address.
    function action_offerOwnerRole(address _address) external {
        lock();

        requireOwnerAddress(msg.sender);

        offerOwnerRole(_address);

        unlock();
    }

    /*
        Add Functions
    */

    /// @notice Anyone can call this to add funds to the bonus prize pool, but only if the contract is not corrupt.
    function add_bonusPrizePool() external payable {
        lock();

        requireNotCorruptContract();

        addBonusPrizePool(msg.value);

        unlock();
    }

    /// @notice The operator can call this to give funds to the contract.
    function add_contractFunds() external payable {
        lock();

        requireOperatorAddress(msg.sender);

        addContractFunds(msg.value);

        unlock();
    }

    /*
        Withdraw Functions
    */

    /// @notice Anyone can call this to withdraw any claimable balance they have.
    function withdraw_addressClaimableBalance() external {
        lock();

        withdrawAddressClaimableBalance(msg.sender);

        unlock();
    }

    /// @notice Anyone can call this to withdraw a refund if a lottery is canceled.
    /// @param _lotteryNumber The number of a lottery.
    function withdraw_addressRefund(uint _lotteryNumber) external {
        lock();

        requireLotteryCanceled(_lotteryNumber);

        withdrawAddressRefund(_lotteryNumber, msg.sender);

        unlock();
    }

    /// @notice The operator can call this to withdraw all Chainlink, subject to a possible minimum reserve requirement.
    function withdraw_allChainlinkBalance() external {
        lock();

        requireOperatorAddress(msg.sender);
        requireTokenWithdrawAllowed(CHAINLINK_TOKEN_ADDRESS, getTokenBalance(CHAINLINK_TOKEN_ADDRESS));

        withdrawAllChainlinkBalance(msg.sender);

        unlock();
    }

    /// @notice The operator can call this to withdraw all contract funds.
    function withdraw_allContractFunds() external {
        lock();

        requireOperatorAddress(msg.sender);
        requireWithdrawAllowed(getOperatorContractBalance());

        withdrawAllContractFunds(msg.sender);

        unlock();
    }

    /// @notice The operator can withdraw all of one kind of token, subject to a possible minimum reserve requirement.
    /// @param tokenAddress The address where the token's contract lives.
    function withdraw_allTokenBalance(address tokenAddress) external {
        lock();

        requireOperatorAddress(msg.sender);
        requireTokenWithdrawAllowed(tokenAddress, getTokenBalance(tokenAddress));

        withdrawAllTokenBalance(tokenAddress, msg.sender);

        unlock();
    }

    /// @notice The operator can call this to withdraw any amount of Chainlink, subject to a possible minimum reserve requirement.
    /// @param value The amount of Chainlink to withdraw.
    function withdraw_chainlinkBalance(uint value) external {
        lock();

        requireOperatorAddress(msg.sender);
        requireTokenWithdrawAllowed(CHAINLINK_TOKEN_ADDRESS, value);

        withdrawChainlinkBalance(msg.sender, value);

        unlock();
    }

    /// @notice The operator can call this to withdraw any amount of the contract funds.
    /// @param value The amount of contract funds to withdraw.
    function withdraw_contractFunds(uint value) external {
        lock();

        requireOperatorAddress(msg.sender);
        requireWithdrawAllowed(value);

        withdrawContractFunds(msg.sender, value);

        unlock();
    }

    /// @notice The operator can trigger a claimable balance withdraw for someone else.
    /// @param _address The address that the operator is triggering the claimable balance withdraw for.
    function withdraw_otherAddressClaimableBalance(address _address) external {
        lock();

        requireOperatorAddress(msg.sender);

        withdrawAddressClaimableBalance(_address);

        unlock();
    }

    /// @notice The operator can trigger a refund withdraw for someone else if a lottery is canceled.
    /// @param _lotteryNumber The number of a lottery.
    /// @param _address The address that the operator is triggering the refund withdraw for.
    function withdraw_otherAddressRefund(uint _lotteryNumber, address _address) external {
        lock();

        requireOperatorAddress(msg.sender);
        requireLotteryCanceled(_lotteryNumber);

        withdrawAddressRefund(_lotteryNumber, _address);

        unlock();
    }

    /// @notice The operator can withdraw any amount of one kind of token, subject to a possible minimum reserve requirement.
    /// @param tokenAddress The address where the token's contract lives.
    /// @param value The amount of tokens to withdraw.
    function withdraw_tokenBalance(address tokenAddress, uint value) external {
        lock();

        requireOperatorAddress(msg.sender);
        requireTokenWithdrawAllowed(tokenAddress, value);

        withdrawTokenBalance(tokenAddress, msg.sender, value);

        unlock();
    }

    /*
        Query Functions
    */

    /// @notice Returns whether the address is playing in the current lottery.
    /// @param _address The address that we are checking.
    /// @return Whether the address is playing in the current lottery.
    function query_isAddressPlaying(address _address) external view returns (bool) {
        return isAddressPlaying(_address);
    }

    /// @notice Returns whether the contract is currently corrupt.
    /// @return Whether the contract is currently corrupt.
    function query_isCorruptContract() external view returns (bool) {
        return isCorruptContract();
    }

    /// @notice Returns whether we are in the corrupt contract grace period.
    /// @return Whether we are in the corrupt contract grace period.
    function query_isCorruptContractGracePeriod() external view returns (bool) {
        return isCorruptContractGracePeriod();
    }

    /// @notice Returns whether the contract is currently locked.
    /// @return Whether the contract is currently locked.
    function query_isLocked() external view returns (bool) {
        return isLocked();
    }

    /// @notice Returns whether the current lottery is active.
    /// @return Whether the current lottery is active.
    function query_isLotteryActive() external view returns (bool) {
        return isLotteryActive();
    }

    /// @notice Returns whether the current lottery only has one player.
    /// @return Whether the current lottery only has one player.
    function query_isOnePlayerGame() external view returns (bool) {
        return isOnePlayerGame();
    }

    /// @notice Returns whether the address is the operator address.
    /// @param _address The address that we are checking.
    /// @return Whether the address is the operator address.
    function query_isOperatorAddress(address _address) external view returns (bool) {
        return isOperatorAddress(_address);
    }

    /// @notice Returns whether the address is the operator successor address.
    /// @param _address The address that we are checking.
    /// @return Whether the address is the operator successor address.
    function query_isOperatorSuccessorAddress(address _address) external view returns (bool) {
        return isOperatorSuccessorAddress(_address);
    }

    /// @notice Returns whether the address is the owner address.
    /// @param _address The address that we are checking.
    /// @return Whether the address is the owner address.
    function query_isOwnerAddress(address _address) external view returns (bool) {
        return isOwnerAddress(_address);
    }

    /// @notice Returns whether the address is the owner successor address.
    /// @param _address The address that we are checking.
    /// @return Whether the address is the owner successor address.
    function query_isOwnerSuccessorAddress(address _address) external view returns (bool) {
        return isOwnerSuccessorAddress(_address);
    }

    /// @notice Returns whether the address is an eligible player address.
    /// @param _address The address that we are checking.
    /// @return Whether the address is an eligible player address.
    function query_isPlayerAddress(address _address) external view returns (bool) {
        return isPlayerAddress(_address);
    }

    /// @notice Returns whether a retry of drawing a winning ticket is permitted.
    /// @return Whether a retry of drawing a winning ticket is permitted.
    function query_isRetryPermitted() external view returns (bool) {
        return isRetryPermitted();
    }

    /// @notice Returns whether the self-destruct is ready.
    /// @return Whether the self-destruct is ready.
    function query_isSelfDestructReady() external view returns (bool) {
        return isSelfDestructReady();
    }

    /// @notice Returns whether a withdraw of the specified amount of the token would be allowed.
    /// @param tokenAddress The address where the token's contract lives.
    /// @param value The amount of tokens to withdraw.
    /// @return Whether a withdraw of the specified amount of the token would be allowed.
    function query_isTokenWithdrawAllowed(address tokenAddress, uint value) external view returns (bool) {
        return isTokenWithdrawAllowed(tokenAddress, value);
    }

    /// @notice Returns whether a winning ticket has been drawn for the current lottery.
    /// @return Whether a winning ticket has been drawn for the current lottery.
    function query_isWinningTicketDrawn() external view returns (bool) {
        return isWinningTicketDrawn();
    }

    /// @notice Returns whether the current lottery has no players.
    /// @return Whether the current lottery has no players.
    function query_isZeroPlayerGame() external view returns (bool) {
        return isZeroPlayerGame();
    }

    /*
        Get Functions
    */

    /// @notice Returns the contract balance that is accounted for.
    /// @return The contract balance that is accounted for.
    function get_accountedContractBalance() external view returns (uint) {
        return getAccountedContractBalance();
    }

    /// @notice Returns the claimable balance of the address.
    /// @param _address The address that we are checking.
    /// @return The claimable balance of the address.
    function get_addressClaimableBalance(address _address) external view returns (uint) {
        return getAddressClaimableBalance(_address);
    }

    /// @notice Returns the refund the address is entitled to if a lottery is canceled.
    /// @param _lotteryNumber The number of a lottery.
    /// @param _address The address that we are checking.
    /// @return The refund the address is entitled to.
    function get_addressRefund(uint _lotteryNumber, address _address) external view returns (uint) {
        return getAddressRefund(_lotteryNumber, _address);
    }

    /// @notice Returns the number of tickets an address has in the current lottery.
    /// @param _address The address that we are checking.
    /// @return The number of tickets the address has in the current lottery.
    function get_addressTickets(address _address) external view returns (uint) {
        return getAddressTickets(_address);
    }

    /// @notice Returns the predicted number of times that the address will win out of 100 times, truncated to an integer. This is equivalent to the percentage probability of the address winning.
    /// @param _address The address that we are checking.
    /// @return The predicted number of times that the address will win out of 100 times.
    function get_addressWinChanceOutOf100(address _address) external view returns (uint) {
        return getAddressWinChanceOutOf(_address, 100);
    }

    /// @notice Returns the predicted number of times that the address will win out of N times, truncated to an integer. This function can be used to get extra digits in the answer that would normally get truncated.
    /// @param _address The address that we are checking.
    /// @param N The total number of times that we want to know how many times the address will win out of.
    /// @return The predicted number of times that the address will win out of N times.
    function get_addressWinChanceOutOf(address _address, uint N) external view returns (uint) {
        return getAddressWinChanceOutOf(_address, N);
    }

    /// @notice Returns the amount of a token that can be withdrawn.
    /// @param tokenAddress The address where the token's contract lives.
    /// @return The amount of a token that can be withdrawn.
    function get_allowedTokenWithdrawBalance(address tokenAddress) external view returns (uint) {
        return getAllowedTokenWithdrawBalance(tokenAddress);
    }

    /// @notice Returns the bonus prize pool. This is the amount of bonus funds that anyone can donate to "sweeten the pot".
    /// @return The bonus prize pool.
    function get_bonusPrizePool() external view returns (uint) {
        return getBonusPrizePool();
    }

    /// @notice Returns the claimable balance pool. This is the total amount of funds that can currently be claimed.
    /// @return The claimable balance pool.
    function get_claimableBalancePool() external view returns (uint) {
        return getClaimableBalancePool();
    }

    /// @notice Returns the entire contract balance. This includes all funds, even those that are unaccounted for.
    /// @return The entire contract balance.
    function get_contractBalance() external view returns (uint) {
        return getContractBalance();
    }

    /// @notice Returns the amount of contracts funds that have been accounted for. Note that the actual contract balance may be higher.
    /// @return The amount of contracts funds that have been accounted for.
    function get_contractFunds() external view returns (uint) {
        return getContractFunds();
    }

    /// @notice Returns the contract balance that is not accounted for.
    /// @return The contract balance that is not accounted for.
    function get_extraContractBalance() external view returns (uint) {
        return getExtraContractBalance();
    }

    /// @notice Returns the total number of active blocks for the current lottery.
    /// @return The total number of active blocks for the current lottery.
    function get_lotteryActiveBlocks() external view returns (uint) {
        return getLotteryActiveBlocks();
    }

    /// @notice Returns the start block number of the current lottery
    /// @return The start block number of the current lottery
    function get_lotteryBlockNumberStart() external view returns (uint) {
        return getLotteryBlockNumberStart();
    }

    /// @notice Returns the current lottery number.
    /// @return The current lottery number.
    function get_lotteryNumber() external view returns (uint) {
        return getLotteryNumber();
    }

    /// @notice Returns the ticket price of a lottery.
    /// @param _lotteryNumber The number of a lottery.
    /// @return The ticket price of a lottery.
    function get_lotteryTicketPrice(uint _lotteryNumber) external view returns (uint) {
        return getLotteryTicketPrice(_lotteryNumber);
    }

    /// @notice Returns the winner's address of a lottery.
    /// @param _lotteryNumber The number of a lottery.
    /// @return The winner's address of a lottery.
    function get_lotteryWinnerAddress(uint _lotteryNumber) external view returns (address) {
        return getLotteryWinnerAddress(_lotteryNumber);
    }

    /// @notice Returns the winner's prize of a lottery.
    /// @param _lotteryNumber The number of a lottery.
    /// @return The winner's prize of a lottery.
    function get_lotteryWinnerPrize(uint _lotteryNumber) external view returns (uint) {
        return getLotteryWinnerPrize(_lotteryNumber);
    }

    /// @notice Returns the operator address.
    /// @return The operator address.
    function get_operatorAddress() external view returns (address) {
        return getOperatorAddress();
    }

    /// @notice Returns the contract balance that the operator has access to.
    /// @return The contract balance that the operator has access to.
    function get_operatorContractBalance() external view returns (uint) {
        return getOperatorContractBalance();
    }

    /// @notice Returns the operator successor address.
    /// @return The operator successor address.
    function get_operatorSuccessorAddress() external view returns (address) {
        return getOperatorSuccessorAddress();
    }

    /// @notice Returns the owner address.
    /// @return The owner address.
    function get_ownerAddress() external view returns (address) {
        return getOwnerAddress();
    }

    /// @notice Returns the owner successor address.
    /// @return The owner successor address.
    function get_ownerSuccessorAddress() external view returns (address) {
        return getOwnerSuccessorAddress();
    }

    /// @notice Returns the penalty the operator must pay to cancel the current lottery. Note that this amount may increase later.
    /// @return The penalty the operator must pay to cancel the current lottery.
    function get_penaltyPayment() external view returns (uint) {
        return getPenaltyPayment();
    }

    /// @notice Returns the player prize pool. This is the amount of funds used to purchase tickets in the current lottery.
    /// @return The player prize pool.
    function get_playerPrizePool() external view returns (uint) {
        return getPlayerPrizePool();
    }

    /// @notice Returns the refund pool. This is the total amount of funds that can currently be refunded from canceled lotteries.
    /// @return The refund pool.
    function get_refundPool() external view returns (uint) {
        return getRefundPool();
    }

    /// @notice Returns the remaining grace period blocks.
    /// @return The remaining grace period blocks.
    function get_remainingCorruptContractGracePeriodBlocks() external view returns (uint) {
        return getRemainingCorruptContractGracePeriodBlocks();
    }

    /// @notice Returns the remaining number of active blocks for the current lottery.
    /// @return The remaining number of active blocks for the current lottery.
    function get_remainingLotteryActiveBlocks() external view returns (uint) {
        return getRemainingLotteryActiveBlocks();
    }

    /// @notice Returns the ticket price of the current lottery.
    /// @return The ticket price of the current lottery.
    function get_ticketPrice() external view returns (uint) {
        return getTicketPrice();
    }

    /// @notice Returns the balance of a token.
    /// @param tokenAddress The address where the token's contract lives.
    /// @return The balance of a token.
    function get_tokenBalance(address tokenAddress) external view returns (uint) {
        return getTokenBalance(tokenAddress);
    }

    /// @notice Returns the minimum reserve requirement of a token.
    /// @param tokenAddress The address where the token's contract lives.
    /// @return The minimum reserve requirement of a token.
    function get_tokenMinimumReserve(address tokenAddress) external view returns (uint) {
        return getTokenMinimumReserve(tokenAddress);
    }

    /// @notice Returns the total number of tickets in the current lottery.
    /// @return The total number of tickets in the current lottery.
    function get_totalTickets() external view returns (uint) {
        return getTotalTickets();
    }

    /*
        Set Functions
    */

    /// @notice The operator can call this to change the total number of active blocks for the lottery. This change will go into effect starting from the next lottery.
    /// @param newLotteryActiveBlocks The new total number of active blocks for the lottery.
    function set_lotteryActiveBlocks(uint newLotteryActiveBlocks) external {
        lock();

        requireOperatorAddress(msg.sender);

        setLotteryActiveBlocks(newLotteryActiveBlocks);

        unlock();
    }

    /// @notice The operator can call this to change the ticket price of the lottery. This change will go into effect starting from the next lottery.
    /// @param newTicketPrice The new ticket price of the lottery.
    function set_ticketPrice(uint newTicketPrice) external {
        lock();

        requireOperatorAddress(msg.sender);

        setTicketPrice(newTicketPrice);

        unlock();
    }

    /*
        Diagnostic Functions
    */

    /// @notice The owner can call this to get information about the internal state of the contract.
    function diagnostic_contractVariables() external view returns (address _operatorAddress, address _operatorSuccessorAddress, address _ownerAddress, address _ownerSuccessorAddress, bool _corruptContractFlag, bool _lockFlag, uint _corruptContractBlockNumber) {
        requireOwnerAddress(msg.sender);

        return(operatorAddress, operatorSuccessorAddress, ownerAddress, ownerSuccessorAddress, corruptContractFlag, lockFlag, corruptContractBlockNumber);
    }

    /// @notice The owner can call this to get information about the internal state of the contract.
    function diagnostic_fundVariables() external view returns (uint _bonusPrizePool, uint _claimableBalancePool, uint _contractFunds, uint _playerPrizePool, uint _refundPool) {
        requireOwnerAddress(msg.sender);

        return(bonusPrizePool, claimableBalancePool, contractFunds, playerPrizePool, refundPool);
    }

    /// @notice The owner can call this to get information about the internal state of the contract.
    function diagnostic_lotteryVariables() external view returns (bool _winningTicketFlag, uint _currentTicketNumber, uint _lotteryActiveBlocks, uint _lotteryBlockNumberStart, uint _lotteryNumber, uint _nextLotteryActiveBlocks, uint _nextTicketPrice, uint _ticketPrice, uint _winningTicket) {
        requireOwnerAddress(msg.sender);

        return(winningTicketFlag, currentTicketNumber, lotteryActiveBlocks, lotteryBlockNumberStart, lotteryNumber, nextLotteryActiveBlocks, nextTicketPrice, ticketPrice, winningTicket);
    }

    /// @notice The owner can call this to get information about the internal state of the contract.
    function diagnostic_chainlinkVariables() external view returns (bool _chainlinkRequestIdFlag, uint _chainlinkRequestId, uint _chainlinkRequestIdBlockNumber, uint _chainlinkRetryCounter) {
        requireOwnerAddress(msg.sender);

        return(chainlinkRequestIdFlag, chainlinkRequestId, chainlinkRequestIdBlockNumber, chainlinkRetryCounter);
    }

    /*
        Fail-Safe Functions
    */

    /// @notice The owner can call this to destroy a corrupt contract.
    function failsafe_selfdestruct() external {
        requireOwnerAddress(msg.sender);
        requireSelfDestructReady();

        selfDestruct(msg.sender);
    }

    /// @notice The owner can call this to make themselves the operator.
    function failsafe_takeOperatorRole() external {
        requireOwnerAddress(msg.sender);

        setOperatorAddress(msg.sender);
        setOperatorSuccessorAddress(msg.sender);
    }

    /// @notice The owner can call this to uncorrupt the contract.
    function failsafe_uncorrupt() external {
        requireOwnerAddress(msg.sender);

        setCorruptContract(false);
    }

    /// @notice The owner can call this to unlock the contract.
    function failsafe_unlock() external {
        requireOwnerAddress(msg.sender);

        setLocked(false);
    }

    /// @notice The owner can call this to validate the contract. If the contract's state is inconsistent, it will be marked as corrupt.
    function failsafe_validate() external {
        requireOwnerAddress(msg.sender);

        validate();
    }
}