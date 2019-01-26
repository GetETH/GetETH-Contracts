pragma solidity ^0.4.24;

import './IERC20.sol';
import './ERC20Detailed.sol';
import './SafeMath.sol';
import './Ownable.sol';

/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
 * Originally based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 *
 * This implementation emits additional Approval events, allowing applications to reconstruct the allowance status for
 * all accounts just by listening to said events. Note that this isn't required by the specification, and other
 * compliant implementations may not do it.
 */
contract ERC20 is IERC20 {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowed;
    uint256 private _totalSupply;

    /**
    * @dev Total number of tokens in existence
    */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
    * @dev Gets the balance of the specified address.
    * @param owner The address to query the balance of.
    * @return An uint256 representing the amount owned by the passed address.
    */
    function balanceOf(address owner) public view returns (uint256) {
        return _balances[owner];
    }

    /**
     * @dev Function to check the amount of tokens that an owner allowed to a spender.
     * @param owner address The address which owns the funds.
     * @param spender address The address which will spend the funds.
     * @return A uint256 specifying the amount of tokens still available for the spender.
     */
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowed[owner][spender];
    }

    /**
    * @dev Transfer token for a specified address
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    */
    function transfer(address to, uint256 value) public returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
     * Beware that changing an allowance with this method brings the risk that someone may use both the old
     * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
     * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     */
    function approve(address spender, uint256 value) public returns (bool) {
        require(spender != address(0));

        _allowed[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Transfer tokens from one address to another.
     * Note that while this function emits an Approval event, this is not required as per the specification,
     * and other compliant implementations may not emit the event.
     * @param from address The address which you want to send tokens from
     * @param to address The address which you want to transfer to
     * @param value uint256 the amount of tokens to be transferred
     */
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        _allowed[from][msg.sender] = _allowed[from][msg.sender].sub(value);
        _transfer(from, to, value);
        emit Approval(from, msg.sender, _allowed[from][msg.sender]);
        return true;
    }

    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     * approve should be called when allowed_[_spender] == 0. To increment
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * Emits an Approval event.
     * @param spender The address which will spend the funds.
     * @param addedValue The amount of tokens to increase the allowance by.
     */
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        require(spender != address(0));

        _allowed[msg.sender][spender] = _allowed[msg.sender][spender].add(addedValue);
        emit Approval(msg.sender, spender, _allowed[msg.sender][spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner allowed to a spender.
     * approve should be called when allowed_[_spender] == 0. To decrement
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * Emits an Approval event.
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        require(spender != address(0));

        _allowed[msg.sender][spender] = _allowed[msg.sender][spender].sub(subtractedValue);
        emit Approval(msg.sender, spender, _allowed[msg.sender][spender]);
        return true;
    }

    /**
    * @dev Transfer token for a specified addresses
    * @param from The address to transfer from.
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    */
    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0));

        _balances[from] = _balances[from].sub(value);
        _balances[to] = _balances[to].add(value);
        emit Transfer(from, to, value);
    }

    /**
     * @dev Internal function that mints an amount of the token and assigns it to
     * an account. This encapsulates the modification of balances such that the
     * proper events are emitted.
     * @param account The account that will receive the created tokens.
     * @param value The amount that will be created.
     */
    function _mint(address account, uint256 value) internal {
        require(account != address(0));

        _totalSupply = _totalSupply.add(value);
        _balances[account] = _balances[account].add(value);
        emit Transfer(address(0), account, value);
    }

    /**
     * @dev Internal function that burns an amount of the token of a given
     * account.
     * @param account The account whose tokens will be burnt.
     * @param value The amount that will be burnt.
     */
    function _burn(address account, uint256 value) internal {
        require(account != address(0));

        _totalSupply = _totalSupply.sub(value);
        _balances[account] = _balances[account].sub(value);
        emit Transfer(account, address(0), value);
    }
}

contract BonusToken is ERC20, ERC20Detailed, Ownable {

    address public gameAddress;
    address public investTokenAddress;
    uint public maxLotteryParticipants;

    mapping (address => uint256) public ethLotteryBalances;
    address[] public ethLotteryParticipants;
    uint256 public ethLotteryBank;
    bool public isEthLottery;

    mapping (address => uint256) public tokensLotteryBalances;
    address[] public tokensLotteryParticipants;
    uint256 public tokensLotteryBank;
    bool public isTokensLottery;

    modifier onlyGame() {
        require(msg.sender == gameAddress);
        _;
    }

    modifier tokenIsAvailable {
        require(investTokenAddress != address(0));
        _;
    }

    constructor (address startGameAddress) public ERC20Detailed("Bet Token", "BET", 18) {
        setGameAddress(startGameAddress);
    }

    function setGameAddress(address newGameAddress) public onlyOwner {
        require(newGameAddress != address(0));
        gameAddress = newGameAddress;
    }

    function buyTokens(address buyer, uint256 tokensAmount) public onlyGame {
        _mint(buyer, tokensAmount * 10**18);
    }

    function startEthLottery() public onlyGame {
        isEthLottery = true;
    }

    function startTokensLottery() public onlyGame tokenIsAvailable {
        isTokensLottery = true;
    }

    function restartEthLottery() public onlyGame {
        for (uint i = 0; i < ethLotteryParticipants.length; i++) {
            ethLotteryBalances[ethLotteryParticipants[i]] = 0;
        }
        ethLotteryParticipants = new address[](0);
        ethLotteryBank = 0;
        isEthLottery = false;
    }

    function restartTokensLottery() public onlyGame tokenIsAvailable {
        for (uint i = 0; i < tokensLotteryParticipants.length; i++) {
            tokensLotteryBalances[tokensLotteryParticipants[i]] = 0;
        }
        tokensLotteryParticipants = new address[](0);
        tokensLotteryBank = 0;
        isTokensLottery = false;
    }

    function updateEthLotteryBank(uint256 value) public onlyGame {
        ethLotteryBank = ethLotteryBank.sub(value);
    }

    function updateTokensLotteryBank(uint256 value) public onlyGame {
        tokensLotteryBank = tokensLotteryBank.sub(value);
    }

    function swapTokens(address account, uint256 tokensToBurnAmount) public {
        require(msg.sender == investTokenAddress);
        _burn(account, tokensToBurnAmount);
    }

    function sendToEthLottery(uint256 value) public {
        require(!isEthLottery);
        require(ethLotteryParticipants.length < maxLotteryParticipants);
        address account = msg.sender;
        _burn(account, value);
        if (ethLotteryBalances[account] == 0) {
            ethLotteryParticipants.push(account);
        }
        ethLotteryBalances[account] = ethLotteryBalances[account].add(value);
        ethLotteryBank = ethLotteryBank.add(value);
    }

    function sendToTokensLottery(uint256 value) public tokenIsAvailable {
        require(!isTokensLottery);
        require(tokensLotteryParticipants.length < maxLotteryParticipants);
        address account = msg.sender;
        _burn(account, value);
        if (tokensLotteryBalances[account] == 0) {
            tokensLotteryParticipants.push(account);
        }
        tokensLotteryBalances[account] = tokensLotteryBalances[account].add(value);
        tokensLotteryBank = tokensLotteryBank.add(value);
    }

    function ethLotteryParticipants() public view returns(address[]) {
        return ethLotteryParticipants;
    }

    function tokensLotteryParticipants() public view returns(address[]) {
        return tokensLotteryParticipants;
    }

    function setInvestTokenAddress(address newInvestTokenAddress) external onlyOwner {
        require(newInvestTokenAddress != address(0));
        investTokenAddress = newInvestTokenAddress;
    }

    function setMaxLotteryParticipants(uint256 participants) external onlyOwner {
        maxLotteryParticipants = participants;
    }
}
