pragma solidity ^0.4.24;

import './SafeMath.sol';
import 'https://github.com/oraclize/ethereum-api/oraclizeAPI_0.4.25.sol';
import './Ownable.sol';
import './BonusToken.sol';

contract Game is usingOraclize, Ownable {
    using SafeMath for uint;

    uint public constant GAME_COIN_FlIP = 0;
    uint public constant GAME_DICE = 1;
    uint public constant GAME_TWO_DICE = 2;
    uint public constant GAME_ETHEROLL = 3;
    uint public constant LOTTERY_FEE = 0.002 ether;
    uint public constant BENEFICIAR_FEE_PERCENT = 2;
    uint public constant MIN_BET = 0.01 ether;

    struct Query {
        uint amount;
        address gamer;
        uint[] values;
        uint prize;
        uint range;
        uint game;
        uint time;
        bool ended;
    }
    mapping(bytes32 => Query) public queries;
    mapping(address => uint) public waitingPrizes;
    mapping(address => bool) public isBet;
    mapping(address => uint) public betsBalances;
    mapping(address => uint) public minRanges;
    mapping(address => uint) public maxRanges;
    address[] public tokensHolders;
    address[] public players;
    bytes32 public lotteryQueryId;
    uint public lotterySize;
    uint public lotteryStage;
    uint public lotteryRound;
    uint public lastLotteryTime;
    uint public lastSendBonusTokensTime;
    uint public callbackGas; // Gas for user __callback function by Oraclize
    uint public beneficiarFund;
    address public beneficiar;
    BonusToken public token;

    uint private playersIndex;

    event PlaceBet(address indexed gamer, bytes32 queryId);
    event Bet(address indexed gamer, uint indexed game, uint amount, uint result, uint[] winResult, uint prize, uint timestamp);
    event WinLottery(address indexed gamer, uint prize, uint ticketsAmount, uint indexed round);

    constructor(address startBeneficiar) public valideAddress(startBeneficiar) {
        oraclize_setProof(proofType_Ledger);
        oraclize_setCustomGasPrice(5000000000); // 5 gwei
        callbackGas = 300000;
        beneficiar = startBeneficiar;
    }

    modifier valideAddress(address addr) {
        require(addr != address(0));
        _;
    }

    /*
    * @param game Game mode (0, 1, 2, 3), watch constants
    * @param values User selected numbers, length = 1 for coin flip game
    * @param referrer Referrer address (default is 0x0)
    *
    * NOTE: ALL USER NUMBERS START WITH 0
    * NOTE: ALL USER NUMBERS MUST GO ASCENDING
    *
    * call this function for place bet to coin flip game with number 0 (eagle)
    * placeBet(0, [0]);
    *
    * call this function for place bet to dice game with numbers 1, 2, 3, 4
    * placeBet(1, [0, 1, 2, 3]);
    *
    * call this function for place bet to two dice game with numbers 2, 3, 4, 7, 8, 11, 12
    * placeBet(2, [0, 1, 2, 5, 6, 9, 10]);
    *
    * call this function for place bet to etheroll game with numbers 1-38
    * placeBet(3, [37]);
    */
    function placeBet(uint game, uint[] values) payable external {
        require(msg.value >= MIN_BET);
        require(game == GAME_COIN_FlIP || game == GAME_DICE || game == GAME_TWO_DICE || game == GAME_ETHEROLL);
        require(valideBet(game, values));
        uint range;
        uint winChance;
        if (game == GAME_COIN_FlIP) {
            require(values.length == 1);
            range = 2;
            winChance = 5000;
        } else if (game == GAME_DICE) {
            require(values.length <= 5);
            range = 6;
            winChance = 1667;
            winChance = winChance.mul(values.length);
        } else if (game == GAME_TWO_DICE) {
            require(values.length <= 10);
            range = 11;
            for (uint i = 0; i < values.length; i++) {
                if (values[i] == 0 || values[i] == 10) winChance = winChance.add(278);
                else if (values[i] == 1 || values[i] == 9) winChance = winChance.add(556);
                else if (values[i] == 2 || values[i] == 8) winChance = winChance.add(833);
                else if (values[i] == 3 || values[i] == 7) winChance = winChance.add(1111);
                else if (values[i] == 4 || values[i] == 6) winChance = winChance.add(1389);
                else if (values[i] == 5) winChance = winChance.add(1667);
            }
        } else if (game == GAME_ETHEROLL) {
            require(values.length == 1);
            range = 100;
            winChance = uint(100).mul(values[0] + 1);
        }
        address sender = msg.sender;
        uint weiAmount = msg.value;
        if (!isBet[sender]) {
            players.push(sender);
            isBet[sender] = true;
        }
        bytes32 queryId = random();
        weiAmount = fee(weiAmount);
        betsBalances[sender] = betsBalances[sender].add(weiAmount);
        uint prize = weiAmount.mul(10000).div(winChance);
        newQuery(queryId, msg.value, sender, values, prize, range);
        queries[queryId].game = game;
        emit PlaceBet(sender, queryId);
    }

    function lottery() external onlyOwner valideAddress(address(token)) {
        require(now - lastLotteryTime >= 24 hours);
        require(token.ethLotteryBank() > 0);
        require(lotterySize > 0);
        if (!token.isEthLottery()) {
            address[] memory lotteryParticipants = token.ethLotteryParticipants();
            for (uint i = 0; i < lotteryParticipants.length; i++) {
                address participant = lotteryParticipants[i];
                uint participantBalance = token.ethLotteryBalances(participant);
                if (participantBalance > 0) {
                    tokensHolders.push(participant);
                }
            }
            updateLotteryRanges();
            lotteryRound++;
        }
        token.startEthLottery();
        lotteryQueryId = random();
    }

    function sendBonusTokens(uint playersIterations) external onlyOwner {
        require(now - lastSendBonusTokensTime >= 24 hours);
        uint playersIterationsNumber;
        if (players.length.sub(playersIndex) < playersIterations) {
            playersIterationsNumber = players.length.sub(playersIndex);
        } else {
            playersIterationsNumber = playersIterations;
        }
        for (uint i; i < playersIterationsNumber; i++) {
            address player = players[playersIndex];
            uint tokensAmount;
            uint betBalance = betsBalances[player];
            while (betBalance >= 1 ether) {
                tokensAmount = tokensAmount.add(100);
                betBalance = betBalance.sub(1 ether);
            }
            if (tokensAmount > 0) {
                token.buyTokens(player, tokensAmount);
            }
            playersIndex++;
        }
        if (playersIndex == players.length) {
            playersIndex = 0;
            lastSendBonusTokensTime = now;
        }
    }

    function refund() external {
        require(waitingPrizes[msg.sender] > 0, '0');
        require(address(this).balance >= waitingPrizes[msg.sender]);
        waitingPrizes[msg.sender] = 0;
        msg.sender.transfer(waitingPrizes[msg.sender]);
    }

    function refundBet(bytes32 queryId) external {
        require(!queries[queryId].ended);
        require(now - queries[queryId].time > 24 hours);
        queries[queryId].ended = true;
        msg.sender.transfer(queries[queryId].amount);
    }

    function getPlayers() external view returns(address[]) {
        return players;
    }

    function setOraclizeGasPrice(uint gasPrice) external onlyOwner {
        oraclize_setCustomGasPrice(gasPrice);
    }

    function setOraclizeGasLimit(uint gasLimit) external onlyOwner {
        callbackGas = gasLimit;
    }

    function setBeneficiarAddress(address newBeneficiar) external onlyOwner valideAddress(newBeneficiar) {
        beneficiar = newBeneficiar;
    }

    function setTokenAddress(address tokenAddress) external onlyOwner valideAddress(tokenAddress) {
        token = BonusToken(tokenAddress);
    }

    function getFund(uint weiAmount) external onlyOwner {
        msg.sender.transfer(weiAmount);
    }

    function getBeneficiarFund() external {
        require(msg.sender == beneficiar);
        uint256 fund = beneficiarFund;
        beneficiarFund = 0;
        beneficiar.transfer(fund);
    }

    function __callback(bytes32 myId, string result, bytes proof) public {
        require((msg.sender == oraclize_cbAddress()), 'Sender must be Oraclize');
        Query storage query = queries[myId];
        require(!query.ended);
        uint randomNumber;
        uint i;
        if (query.gamer != address(0)) {
            if (oraclize_randomDS_proofVerify__returnCode(myId, result, proof) != 0) {
                sendWin(query.gamer, query.amount);
            } else {
                randomNumber = uint(keccak256(result)) % query.range;
                bool isWin;
                for (i = 0; i < query.values.length; i++) {
                    if (query.game == GAME_ETHEROLL) {
                        if (randomNumber <= query.values[i]) {
                            sendWin(query.gamer, query.prize);
                            isWin = true;
                        }
                    } else {
                        if (randomNumber == query.values[i]) {
                            sendWin(query.gamer, query.prize);
                            isWin = true;
                            break;
                        }
                    }
                }
                if (isWin) {
                    emit Bet(query.gamer, query.game, query.amount, randomNumber, query.values, query.prize, now);
                } else {
                    emit Bet(query.gamer, query.game, query.amount, randomNumber, query.values, 0, now);
                }
            }
            query.ended = true;
        } else if (myId == lotteryQueryId) {
            require(oraclize_randomDS_proofVerify__returnCode(myId, result, proof) == 0);
            randomNumber = uint(keccak256(result)) % token.ethLotteryBank();
            uint prize = 0;
            if (lotteryStage == 0) {
                prize = lotterySize.div(2);
            } else if (lotteryStage == 1) {
                prize = lotterySize.div(4);
            } else if (lotteryStage == 2) {
                prize = lotterySize.mul(12).div(100);
            } else if (lotteryStage == 3) {
                prize = lotterySize.mul(8).div(100);
            } else {
                prize = lotterySize.div(20);
            }
            for (i = 0; i < tokensHolders.length; i++) {
                address tokensHolder = tokensHolders[i];
                if (randomNumber >= minRanges[tokensHolder] && randomNumber < maxRanges[tokensHolder]) {
                    deleteTokensHolder(i);
                    sendWin(tokensHolder, prize);
                    emit WinLottery(tokensHolder, prize, token.ethLotteryBalances(tokensHolder), lotteryRound);
                    lotteryStage++;
                    updateLotteryRanges();
                    token.updateEthLotteryBank(token.ethLotteryBalances(tokensHolder));
                    break;
                }
            }
            if (lotteryStage == 5 || tokensHolders.length == 0) {
                tokensHolders = new address[](0);
                lotterySize = 0;
                lotteryStage = 0;
                lastLotteryTime = now;
                token.restartEthLottery();
            } else {
                lotteryQueryId = random();
            }
        }
    }

    function updateLotteryRanges() private {
        uint range = 0;
        for (uint i = 0; i < tokensHolders.length; i++) {
            address participant = tokensHolders[i];
            uint participantBalance = token.ethLotteryBalances(participant);
            minRanges[participant] = range;
            range = range.add(participantBalance);
            maxRanges[participant] = range;
        }
    }

    function valideBet(uint game, uint[] values) private pure returns(bool) {
        require(values.length > 0);
        for (uint i = 0; i < values.length; i++) {
            if (i == 0) {
                if (game == GAME_ETHEROLL && values[i] > 96) {
                    return false;
                }
            }
            if (i != values.length - 1) {
                if (values[i + 1] <= values[i]) {
                    return false;
                }
            }
        }
        return true;
    }

    function fee(uint weiAmount) private returns(uint) {
        uint beneficiarFee = weiAmount.mul(BENEFICIAR_FEE_PERCENT).div(100);
        beneficiarFund = beneficiarFund.add(beneficiarFee);
        lotterySize = lotterySize.add(LOTTERY_FEE);
        weiAmount = weiAmount.sub(beneficiarFee).sub(LOTTERY_FEE);
        return weiAmount;
    }

    function newQuery(bytes32 queryId, uint amount, address gamer, uint[] values, uint prize, uint range) private {
        queries[queryId].gamer = gamer;
        queries[queryId].amount = amount;
        queries[queryId].values = values;
        queries[queryId].prize = prize;
        queries[queryId].range = range;
        queries[queryId].time = now;
    }

    function random() private returns(bytes32 queryId) {
        require(address(this).balance >= oraclize_getPrice('random', callbackGas));
        queryId = oraclize_newRandomDSQuery(0, 4, callbackGas);
        require(queryId != 0, 'Oraclize error');
    }

    function sendWin(address winner, uint weiAmount) private {
        if (address(this).balance >= weiAmount) {
            winner.transfer(weiAmount);
        } else {
            waitingPrizes[winner] = waitingPrizes[winner].add(weiAmount);
        }
    }

    function deleteTokensHolder(uint index) private {
        tokensHolders[index] = tokensHolders[tokensHolders.length - 1];
        delete tokensHolders[tokensHolders.length - 1];
        tokensHolders.length--;
    }
}
