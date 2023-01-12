/**
 * @title WebDemocracy - Arbitration contract
 * @dev This contract allows to buy DEM tokens and stake them to be elegible as Juror. The Jury can be elegible
 * after staking the DEM tokens. When a staker is selected as Juror for a specific dispute, the Juror must check
 * all the proves updated by the complainants in www.WebDemocracy.com. All the parties will need to log in with their
 * wallet to have access.
 *
 * The Disputes are generated by the complainants from a third contract used for selling a product, a service, etc.
 * To generate a dispute, the complainants have to pay a fee in ethers depending on the time each Jury are going to need
 * to give a honest vote for the case.
 *
 * Once the Jury have voted the winner for the Dispute in the time stipulated, the winner will be able to withdraw
 * the locked funds from the contract where they interacted.
 *
 * You are only elegible as Juror if you stake your tokens with a minimum and a maximum amount specified.
 * The way how the Jury are selected is 100% random, but you can have more chances to be selected depending on the amount
 * of tokens staked and the Honesty score.
 *
 * The Jury receive +1 in their honesty score every time they voted to the winner of the dispute, and every time they
 * choose to the looser complainant they will receive -1.
 *
 * This contract keeps track of:
 *      Tokens & Staking
 *      Honesty score
 *      Jury selection
 *      Disputes & votes & results.
 *
 * NOTE: To be able to generate a dispute from a Smart contract, that smart contract needs to import the WebDemocracy.sol
 *       contract. This contract imports ERC20.sol, Ownable.sol and Ecommerce.sol.
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./Ecommerce.sol";

contract WebDemocracy is ERC20, Ownable {
    //**********************//
    //   Enums and Structs  //
    //**********************//
    enum DisputeStatus {
        Started, // When the dispute is under voting.
        UnderApelation, // When the dispute is under Apelation.
        Finished // When the dispute is finished and there is a final winner.
    }

    struct Dispute {
        address buyer; // The buyer in the Smartcontract under Arbitrage.
        address seller; // The seller in the Smartcontract under Arbitrage.
        Ecommerce disputaSC; // Arbitrage contract. (The contract that started the dispute)
        bool active; // Toggle to check if the Dispute is active or finished.
        uint256 comision; // Total comision paid by the complainants. (1/2 will be shared to WD and the Jury)
        uint256 timeToVote; // Total time to place the vote.
        uint8 buyerCount; // Votes count for the buyer
        uint8 sellerCount; // Votes count for the seller.
        uint8 juryNeeded; // Amount of Jury needed for the case.
        uint8 appealTime; // 1 days.
        uint8 appealCount; // How many times the appelation process was done;
        DisputeStatus disputeStatus; // Actual status for the dispute.
    }

    modifier protocolActive() {
        require(protocolWorking, "Protocol under maintenance");
        _;
    }

    //**********************//
    //       Variables      //
    //**********************//

    /* Variables which should not change after initialization.*/
    address payable private webDemocracy; // Our own address, to get the 3% of comissions

    /* Variables which will subject to the governance mechanism.*/
    uint256 private disputesCounter; // Total disputes created.
    uint256 private penaltyFee = 100; // Penalty fee for no voting in time.
    uint256 private tokenPrice = 0.0001 ether;
    uint256 private arbitrationFeePerJuror = 0.005 ether; // Fee per juror.
    uint8 private protocolFee = 3; // WebDemocracy Fee %.
    bool private sellingTokens = true; // Toggle to sell or stop selling tokens.
    bool private protocolWorking = true; // Toggle to accept or not accept new Disputes.

    //**********************//
    //       Mapping        //
    //**********************//

    mapping(address => uint256) public tokensStaked; // Juror address => tokens staked (uint)
    mapping(uint256 => Dispute) private disputeInfo; // DisputeID => Dispute info => Dispute details.
    mapping(uint256 => mapping(address => bool)) public disputeActive; // DisputeID => Dispute (address) => Dispute active (boolean)
    mapping(uint256 => address) private winner; // DisputeID => winner;
    mapping(address => bool) private jurorStaking; // Juror address => Juror staking (boolean)
    mapping(address => bool) private stakedOnce; // Juror address => Juror staked at least once (boolean)
    mapping(uint256 => address[]) private juryDispute; // DisputeID => Jury selected for that dispute (Array with addresses)
    mapping(uint256 => mapping(uint8 => mapping(uint8 => address[])))
        private juryDisputeCount; // DisputeID => Dispute(value 1) or Apelation(Value2) => voting Choice(1 Buyer, 2 Seller) => Jury voted (Array with addreses)
    mapping(address => int256) private honestyScore; // Juror address => honesty Score (int + or -)
    mapping(uint256 => mapping(address => bool)) public rightToVote; // Dispute ID => Jury address => Juror has rights to vote (boolean)
    mapping(address => mapping(uint256 => mapping(uint8 => uint8)))
        private jurorVoted; // Juror address => disputeID => Dispute(value 1) or Apelation(Value2) => voting Choice (1 Buyer, 2 Seller)
    mapping(address => bool) private underDispute; // Juror address => Juror under dispute. (Boolean)
    mapping(uint256 => address[]) private appealJury; // disputeID => Jury addresses

    //**********************//
    //        Events        //
    //**********************//

    /*
        @dev Emited when a new dispute is generated.
        @param buyer: The buyer in the Smartcontract under Arbitrage.
        @param seller: The seller in the Smartcontract under Arbitrage.
        @param disputeID: new ID generated for this specific Dispute.
        @param timetoFinish: Total time stablished to vote.
    */
    event DisputeGenerated(
        address indexed buyer,
        address indexed seller,
        uint256 disputeID,
        uint256 timeToFinish
    );

    /**
        @dev Emited when a new purchase of DEM has been done.
        @param buyer: The buyer of the tokens DEM.
        @param amount: Amount purchased.
    */
    event TokenPurchased(address buyer, uint256 amount);

    /**
        @dev Emited when a new Jury is generated.
        @param disputeID: ID representing the dispute.
        @param jurys: Array of the jury selected for the dispute.
    */
    event JuryGenerated(uint256 disputeID, address[] indexed jurys);

    /**
        @dev Emited when a Juror is revocated.
        @param jurorRevocated: Address of the Juror removed from the dispute.
        @param newJuror: Address of the new Juror added to the dispute.
        @param disputeID: ID representing the dispute.
    */
    event JurorRevocated(
        address indexed jurorRevocated,
        address indexed newJuror,
        uint256 disputeID
    );

    /**
        @dev Emited when a new staker stakes.
        @param staker: Address staking DEM.
        @param amount: Amount of tokens DEM staked.
    */
    event NewStaker(address indexed staker, uint256 amount);

    /** 
        @dev Emited when a dispute has finished.
        @param disputeID: ID representing the dispute.
        @param winner: Address selected as winner in the dispute.
    */
    event DisputeFinished(uint256 disputeID, uint8 winner);

    /*
     * @dev Constructor.
     * @param _webDemocracy: Protocol address and Owner.
     * @param webDemocracy: ERC20 token Name.
     * @param DEM: ERC20 token Symbol.
     */
    constructor(address payable _webDemocracy) ERC20("WebDemocracy", "DEM") {
        _mint(address(this), 1000000000000000000000000000); // 1billion + 18 decimals
        webDemocracy = _webDemocracy;
    }

    /**
     * @dev Function used to buy tokens when WebDemocracy launches the private round. It will update the holder and the contract balance.
     * @param _amount: The amount willing to buy.
     */
    function buyTokens(uint256 _amount) public payable {
        require(sellingTokens, "Use DEX and CEX");
        uint256 price = _totalPrice(_amount);
        require(msg.value >= price, "Send more ETH");
        uint256 extra = msg.value - price;
        payable(msg.sender).transfer(extra);
        _transfer(address(this), msg.sender, _amount);

        emit TokenPurchased(msg.sender, _amount);
    }

    /**
     * @dev It allow users to move tokens from one to another account.
     * @param _to: Address we want to transfer to.
     * @param _amount: Amount of tokens we want to transfer.
     */
    function transfer(address _to, uint256 _amount)
        public
        override
        returns (bool success)
    {
        _transfer(msg.sender, _to, _amount);
        return success;
    }

    /**
     * @dev It generates new tokens and add them to the total contract balance.
     * @param _amount: Total amount we want to mint.
     */
    function mint(uint256 _amount) public onlyOwner {
        _mint(address(this), _amount);
    }

    /**
     * @dev It transfers tokens from the contract balance to the address(0). (Burning)
     * @param _amount: Total amount we want to burn.
     */
    function burn(uint256 _amount) public onlyOwner {
        _burn(address(this), _amount);
    }

    /**
     * @dev Setter for the stake token array. The minimum to stake is the penalty fee.
     * We want Web Democracy to becomes a fear system, where the maximum staked per juror is 3% of the total supply.
     * @param _amount: Total amount willing to stake
     */
    function stake(uint256 _amount) public {
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");
        require(_amount >= penaltyFee, "minimum PenaltyFee"); // Minimum to stake is the penalty fee
        require(
            (_amount + tokensStaked[msg.sender]) < totalSupply() * (3 * 100),
            "Reached the max to stake"
        );
        // Transfer the tokens to the main contract to be staked
        _transfer(msg.sender, address(this), _amount);
        // Add him to the stakers array if it is the first time the user stakes
        uint256 _tokensStaked = checkTokensStaked(msg.sender);
        if (_tokensStaked == 0 && !stakedOnce[msg.sender]) {
            emit NewStaker(msg.sender, _amount);
        }
        // Update mapping stakers
        tokensStaked[msg.sender] += _amount;
        jurorStaking[msg.sender] = true;
    }

    /**
     * @dev Setter for the stake token array. It can only be called when you are not underDispute,then,
     * the protocol can substract fees in case the Jury did not vote.
     * @param _amount: Total amount willing to unstake.
     */
    function unStake(uint256 _amount, address _juror) public {
        require(
            msg.sender == _juror || msg.sender == webDemocracy,
            "Not your tokens"
        );
        require(tokensStaked[_juror] > 0, "0 tokens staked");
        require(!underDispute[_juror], "Your dispute is not finished");
        // Update mapping tokenStaked
        tokensStaked[_juror] -= _amount;
        // Transfer the tokens back to the staker
        _transfer(address(this), _juror, _amount);
        jurorStaking[_juror] = false;

        if (tokensStaked[_juror] == 0) {
            jurorStaking[_juror] = false;
        }
    }

    /**
     * @dev It starts the Dispute process. Also, it calls the generate random Jury algorithm and stores all the dispute details.
     * To call this function the protocol needs to be Activated and the msg.value must be greater than the Fees needed
     * for paying the Jury.
     * @param _buyer: The buyer in the Smartcontract under Arbitrage.
     * @param _seller: The seller in the Smartcontract under Arbitrage.
     * @param _dificulty: Level of the dispute. Depending on the time needed and Jury needed.
     * @param _juryNeeded: Total number of Jury needed for the dispute.
     */
    function generateDispute(
        address _buyer,
        address _seller,
        uint256 _dificulty,
        uint8 _juryNeeded
    ) external payable protocolActive {
        require(
            msg.value >= arbitrationFeePerJuror * _juryNeeded,
            "Not enough to pay Jury Fee"
        );

        Dispute memory dispute = Dispute(
            _buyer,
            _seller,
            Ecommerce(msg.sender),
            true,
            msg.value,
            _dificulty,
            0,
            0,
            _juryNeeded,
            0 days,
            0,
            DisputeStatus.Started
        );

        disputeInfo[disputesCounter] = dispute;
        disputesCounter++;

        emit DisputeGenerated(_buyer, _seller, disputesCounter, _dificulty);
    }

    /**
     * @dev It generates a sencond dispute. Also, it calls the generate random Jury algorithm and stores all the dispute details.
     * To call this function the protocol needs to be Activated and the msg.value must be greater than the Fees needed
     * for paying the Jury.
     */
    function appeal(
        uint256 _disputeID,
        uint8 _juryNeeded,
        uint256 _dificulty
    ) external payable protocolActive {
        require(
            msg.value >= arbitrationFeePerJuror * _juryNeeded,
            "Not enough to pay Jury fee"
        );
        require(
            disputeInfo[_disputeID].disputeStatus == DisputeStatus.Finished,
            "The dispute has not finished yet"
        );
        require(
            disputeInfo[_disputeID].appealTime < block.timestamp,
            "The appeal time is over"
        );
        require(
            disputeInfo[_disputeID].appealCount == 0,
            "You can appeal just one time"
        );
        require(
            address(disputeInfo[_disputeID].disputaSC) == msg.sender,
            "You need to be the Ecommerce SC"
        );

        disputeInfo[_disputeID].disputeStatus = DisputeStatus.UnderApelation;
        disputeInfo[_disputeID].active = true;
        disputeInfo[_disputeID].appealCount = 1;
        disputeInfo[_disputeID].comision = msg.value;
        disputeInfo[_disputeID].buyerCount = 0;
        disputeInfo[_disputeID].sellerCount = 0;
        disputeInfo[_disputeID].timeToVote = block.timestamp + _dificulty;
        disputeInfo[_disputeID].disputeStatus = DisputeStatus.UnderApelation;

        emit DisputeGenerated(
            disputeInfo[_disputeID].buyer,
            disputeInfo[_disputeID].seller,
            _disputeID,
            disputeInfo[_disputeID].timeToVote
        );
    }

    /*
     *  @dev WebDemocracy.org will listen to the event DisputeGenerated(), when the function generateDispute() is called
     *  and will generate random selection of Jury for the dispute. (Depending on the number of tokens staked and the Jury honesty score)
     *  This function will store the Jury selection to the ID Dispute. But if the Dispute is under Apelation, it will store it in a new array.
     * @param _disputeID: ID representing the Dispute.
     * @param _jurySelected: Jury selected for this specific dispute.
     */
    function storeJurys(uint256 _disputeID, address[] memory _jurySelected)
        public
        onlyOwner
    {
        if (
            disputeInfo[_disputeID].disputeStatus ==
            DisputeStatus.UnderApelation
        ) {
            appealJury[_disputeID] = _jurySelected;
        } else {
            juryDispute[_disputeID] = _jurySelected;
        }

        for (uint256 i; i < _jurySelected.length; i++) {
            rightToVote[_disputeID][_jurySelected[i]] = true;
            underDispute[_jurySelected[i]] = true; // It will store the Jury as underDispute to do not allow unstake.
        }

        emit JuryGenerated(_disputeID, _jurySelected);
    }

    /**
     * @dev It removes the selected Juror from the Jury selected for the ID Dispute. When the event JuryGenerated() is emitted,
     * WebDemocracy will select a new random juror and will store it in the Jury selection for the ID Dispute specified.
     * The protocol keeps the penaltyFee if the Juror did not vote.
     * @param _jurorRevocated: The Juror the protocol removes.
     * @param _newJuror: The new Juror the protocol stores.
     * @param _disputeID: ID representing the Dispute.
     * @param _dificulty: Time given depending on the dificulty. 1 day => 24 * 60 * 60
     */
    function revocateJuror(
        address _jurorRevocated,
        address _newJuror,
        uint256 _disputeID,
        uint256 _dificulty
    ) public onlyOwner {
        uint256 nbJuryDispute = juryDispute[_disputeID].length;
        rightToVote[_disputeID][_newJuror] = true; // Give permissions to vote
        for (uint256 i; i < nbJuryDispute; i++) {
            if (juryDispute[_disputeID][i] == _jurorRevocated) {
                juryDispute[_disputeID][i] = _newJuror;

                penalizeInactiveJuror(_jurorRevocated, _disputeID); // The protocol keeps the penaltyFee if the Juror did not vote
                disputeInfo[_disputeID].timeToVote =
                    block.timestamp +
                    _dificulty; // Update time to vote
            }
        }

        emit JurorRevocated(_jurorRevocated, _newJuror, _disputeID);
    }

    /**
     * @dev It penalizes the penaltyFee to the Jury who did not vote. The protocol will substract the penalty fee from his staking,
     * and it will share it between the Jury winner.
     * @param _jurorLooser: Juror address to substract tokens. (Penalized)
     * @param _disputeID: ID representing the Dispute.
     * @param _jurrorWinner: value of the winner (1 Buyer, 2 Seller)
     */
    function penalizeLoosers(
        address _jurorLooser,
        uint256 _disputeID,
        uint8 _jurrorWinner
    ) internal {
        require(
            tokensStaked[_jurorLooser] >= penaltyFee,
            "Not enough staking for the fee"
        );

        honestyScore[_jurorLooser] -= 1;
        uint8 honestJury;
        uint8 disputeValue; // New dispute -> value: 0, Under apelation -> value: 1

        // Determinate if the Dispute is under apelation or not.
        if (disputeInfo[_disputeID].appealCount == 0) {
            disputeValue = 0;
        } else {
            disputeValue = 1;
        }

        honestJury = uint8(
            juryDisputeCount[_disputeID][disputeValue][_jurrorWinner].length
        );

        uint256 penaltyFeeEachJury = honestJury / penaltyFee; // Jurys who voted honestly share the penaltyFee.
        tokensStaked[_jurorLooser] -= penaltyFee; // Fee will be taken from the juror staking.

        for (uint256 i; i < honestJury; i++) {
            address result = juryDisputeCount[_disputeID][disputeValue][
                _jurrorWinner
            ][i];
            _transfer(_jurorLooser, result, penaltyFeeEachJury);
        }
    }

    /**
     * @dev It penalizes the penaltyFee to the Jury who did not vote. The protocol will substract the penalty fee from his staking,
     * and it will share it between the Jury winner.
     * @param _jurorAddress: Juror address to substract tokens. (Penalized)
     * @param _disputeID: ID representing the Dispute.
     */
    function penalizeInactiveJuror(address _jurorAddress, uint256 _disputeID)
        internal
        onlyOwner
    {
        require(
            disputeInfo[_disputeID].timeToVote < block.timestamp,
            "Voting time is not over"
        );
        require(
            tokensStaked[_jurorAddress] >= penaltyFee,
            "Not enough staking for the fee"
        );

        honestyScore[_jurorAddress] -= 1;
        rightToVote[_disputeID][_jurorAddress] = false; // Remove permissions to vote
        uint8 disputeValue; // New dispute -> value: 0, Under apelation -> value: 1

        // Determinate if the Dispute is under apelation or not.
        if (disputeInfo[_disputeID].appealCount == 0) {
            disputeValue = 0;
        } else {
            disputeValue = 1;
        }
        underDispute[_jurorAddress] = false;
        unStake(penaltyFee, _jurorAddress); // Unstake penaltyFee
        _transfer(_jurorAddress, address(this), penaltyFee); // The protocol keeps the penaltyFee if the Juror did not vote
    }

    /** @dev Function to store a vote and if you are the last Juror voting it will set the winner.
     *  @param _disputeID: ID representing the Dispute.
     *  @param _choose: Voting choose (1 - Buyer or 2 - Seller)
     */
    function vote(uint256 _disputeID, uint8 _choose) public {
        require(
            block.timestamp < disputeInfo[_disputeID].timeToVote,
            "Time to vote is over"
        );
        require(
            rightToVote[_disputeID][msg.sender] == true,
            "You are not allow to vote"
        );
        require(_choose == 1 || _choose == 2, "This option is not available");

        uint8 disputeValue;
        uint8 totalVotes;
        uint8 votesNeeded = disputeInfo[_disputeID].juryNeeded;
        rightToVote[_disputeID][msg.sender] = false;
        // Determinate if the Dispute is under apelation or not.
        if (disputeInfo[_disputeID].appealCount == 0) {
            disputeValue = 0;
        } else {
            disputeValue = 1;
        }

        jurorVoted[msg.sender][_disputeID][disputeValue] = _choose;
        juryDisputeCount[_disputeID][disputeValue][_choose].push(msg.sender);

        if (_choose == 1) {
            disputeInfo[_disputeID].buyerCount += 1;
            totalVotes = (disputeInfo[_disputeID].buyerCount +
                disputeInfo[_disputeID].sellerCount);

            if (totalVotes == votesNeeded) {
                disputeInfo[_disputeID].active = false;
                withdrawalFees(_disputeID);

                emit DisputeFinished(_disputeID, _choose);
            }
        } else if (_choose == 2) {
            disputeInfo[_disputeID].sellerCount += 1;
            totalVotes = (disputeInfo[_disputeID].buyerCount +
                disputeInfo[_disputeID].sellerCount);

            if (totalVotes == votesNeeded) {
                disputeInfo[_disputeID].active = false;
                withdrawalFees(_disputeID);

                emit DisputeFinished(_disputeID, _choose);
            }
        }
    }

    /**
     * @dev This function will be called when the needed votes are filled. Also, it will transfer the fee to the jurys,
     * the protocol fee to WebDemocracy and the paid fee back to the winner.
     * To be triggered, it will listen to the event DisputeFinished() when emited. Also, It will penalize the Jury who
     * voted to the looser complainant.
     * @param _disputeID: ID representing the Dispute.
     */
    function withdrawalFees(uint256 _disputeID) internal {
        require(!disputeInfo[_disputeID].active, "Still waiting for votes");
        disputeInfo[_disputeID].disputeStatus = DisputeStatus.Finished; // Set the Dispute status to Finished.
        uint256 funds = disputeInfo[_disputeID].comision;
        uint256 feeRefund = funds / 2; // Half of the fees paid will be returnd to the winner.
        uint256 feeProtocol = (feeRefund * protocolFee) / 100; // WD keeps 3% of the fee paid from the looser.
        address winnerAddress;
        uint8 votedBuyer = disputeInfo[_disputeID].buyerCount;
        uint8 votedSeller = disputeInfo[_disputeID].sellerCount;
        uint8 disputeValue = disputeInfo[_disputeID].appealCount;

        // Set coldownTime in the Ecommerce contract. Once it has gone over the complainants will not be able to appel
        if (votedBuyer > votedSeller) {
            winnerAddress = disputeInfo[_disputeID].buyer;

            uint256 rewardEach = (feeRefund - feeProtocol) / votedBuyer;

            // Reward
            for (uint256 i; i < votedBuyer; i++) {
                address juror = juryDisputeCount[_disputeID][disputeValue][1][
                    i
                ];
                payable(juror).transfer(rewardEach);
                honestyScore[juror] += 1;
            }

            // Penalize
            for (uint256 i; i < votedSeller; i++) {
                address juror = juryDisputeCount[_disputeID][disputeValue][2][
                    i
                ];
                penalizeLoosers(juror, _disputeID, 1);
                honestyScore[juror] -= 1;
            }
        } else {
            winnerAddress = disputeInfo[_disputeID].seller;

            uint256 rewardEach = (feeRefund - feeProtocol) / votedSeller;

            // Reward
            for (uint256 i; i < votedSeller; i++) {
                address juror = juryDisputeCount[_disputeID][disputeValue][2][
                    i
                ];
                payable(juror).transfer(rewardEach);
                honestyScore[juror] += 1;
            }

            // Penalize
            for (uint256 i; i < votedBuyer; i++) {
                address juror = juryDisputeCount[_disputeID][disputeValue][1][
                    i
                ];
                penalizeLoosers(juror, _disputeID, 2);
                honestyScore[juror] -= 1;
            }
        }
        payable(webDemocracy).transfer(feeProtocol); // Payment for WD
        payable(winnerAddress).transfer(feeRefund); // Fees back to the winner
        (disputeInfo[_disputeID].disputaSC).setWinner(
            winnerAddress,
            _disputeID
        ); // Set winner to be able to withdraw his funds from the Ecommerce contract.
    }

    /**
     * @dev Setter for the Token price while the private round. I can be called only by the Owner.
     * @param _price: New token price we want to set.
     */
    function updateTokenPrice(uint256 _price) public onlyOwner {
        tokenPrice = _price;
    }

    /**
     * @dev Setter stop or reanude the protocol to generate new Disputes.
     *  It can be used while maintenance or if needed.
     */
    function stopStartNewDisputes() public onlyOwner {
        protocolWorking = !protocolWorking;
    }

    /**
     * @dev Setter to update the Fee Web Democracy gets.
     * @param _newFee: New fee we want to set for Web Democracy.
     */
    function updateWDFee(uint8 _newFee) public onlyOwner {
        protocolFee = _newFee;
    }

    /**
     * @dev Setter to stop selling tokens when the private round is finished.
     * @param _status: Value to allow or refuse the token sale.
     */
    function tokenSale(bool _status) private {
        sellingTokens = _status;
    }

    /**
     * @dev Setter to update the Fee each Juror gets.
     * @param _newFee: New fee we want to set for each juror.
     */
    function _setArbitrationFee(uint256 _newFee) internal onlyOwner {
        arbitrationFeePerJuror = _newFee;
    }

    /**
     * @dev Getter for the protocol Fee;
     */
    function _checkProtocolFee() internal view returns (uint256) {
        return protocolFee;
    }

    /**
     * @dev Internal function to get the total price, checking the actual price of the token. (Used during private round)
     * @param _amount: The amount we would like to convert
     */
    function _totalPrice(uint256 _amount) internal view returns (uint256) {
        return _amount * tokenPrice;
    }

    /*
     * @dev Geetter for how many DEM staked has the Juror address.
     * @param _juro: Juror address.
     */
    function checkTokensStaked(address _juror) public view returns (uint256) {
        return tokensStaked[_juror];
    }

    /**
     * @dev Getter for checking if a Juror is staking.
     * @param _juror: Juror address.
     */
    function _isActive(address _juror) internal view returns (bool) {
        return jurorStaking[_juror];
    }

    function _checkDispute(uint256 _disputeID)
        internal
        view
        returns (Dispute memory)
    {
        return disputeInfo[_disputeID];
    }

    function arbitrationFee(uint8 _nbJury) public view returns (uint256) {
        return arbitrationFeePerJuror * _nbJury;
    }

    receive() external payable {}
}
