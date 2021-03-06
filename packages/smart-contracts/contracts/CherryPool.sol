pragma solidity ^0.5.12;

// Library & interfaces
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "./interface/ICERC20.sol";
// Contracts
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "./token/CherryDai.sol";
import "./CherryMath.sol";


/**
 * @title CherryPool Contract
 * @notice This contract handle Cherry Pool functionalities
 */
contract CherryPool is Initializable {
    using SafeMath for uint256;

    address public owner;

    uint256 public poolBalance; // total pool balance in DAI
    uint256 public poolcBalance; // total pool providers cdai balance cDai
    uint256 public longPoolBalance; // long pool balance in DAI
    uint256 public shortPoolBalance; // short pool balance in DAI
    uint256 public longPoolReserved; // amount of DAI reserved in the long pool
    uint256 public shortPoolReserved; // amount of DAI reserved in the short pool
    int256 public poolcTokenProfit; //the total net profit the pool has made in ctokens (or lost) during it life

    IERC20 public token; // collateral asset = DAI
    ICERC20 public cToken; // cDAI token

    CherryDai public cherryDai; // CherryDai token
    CherryMath cherryMath; // Math library

    event DepositLiquidity(address indexed liquidityProvider, uint256 amount);
    event MintCherry(address indexed liquidityProvider, uint256 amountDai,uint256 amountcDai, uint256 amountCherryDai);
    event RedeemCherry(address indexed liquidityProvider, uint256 redeemedCherryDaiDaiAmount);
    event TransferDai(address indexed to, uint256 value);
    event CurrentExchangeRate(uint256 rate);
    event PoolShare(uint256 amount);
    event FreeLongPool(uint256 amount);
    event FreeShortPool(uint256 amount);
    event SetCherryDai(address cherryDai);

    /**
     * @notice Initialize contract states
     */
    function initialize(address _token, address _cToken, address _cherryMath) public initializer {
        owner = msg.sender;

        token = IERC20(_token);
        cToken = ICERC20(_cToken);
        cherryMath = CherryMath(_cherryMath);
    }

    /**
     * @notice Modifier to check if long pool is not fully utilized
     */
    modifier isLongUtilized() {
        require(calcLongPoolUtil(longPoolReserved) < 1e18, "Cherrypool::long pool if fully utilized");
        _;
    }

    /**
     * @notice Modifier to check if short pool is not fully utilized
     */
    modifier isShortUtilized() {
        require(calcShortPoolUtil(shortPoolReserved) < 1e18, "Cherrypool::short pool is fully utilized");
        _;
    }

    modifier canReserveLong(uint256 _amount) {
        require(longPoolReserved.add(_amount) <= longPoolBalance, "Cherrypool::long pool does not have liquidity");
        _;
    }

    modifier canReserveShort(uint256 _amount) {
        require(shortPoolReserved.add(_amount) <= shortPoolBalance, "Cherrypool::short pool does not have liquidity");
        _;
    }

    /**
     * @notice adds liquidity to the cherry pool to offer swaps against
     * @param _amount amount of deposited DAI
     * @return cherryDaiToMint amount of minted CherryDai
     */
    function mint(uint256 _amount) external returns (uint256) {
        require(_amount > 0, "Cherrypool::amount provided must be higher");

        // collect liquidity from provider
        require(token.transferFrom(msg.sender, address(this), _amount), "Cherrypool::deposit liquidity failed");

        // deposit liqudity into compound
        token.approve(address(cToken), _amount);

        // On compound this function's parameter is defined as the amount of the
        // asset to be supplied, in units of the underlying asset. this is the dai amount.
        assert(cToken.mint(_amount) == 0);

        // Get the pools amount in cTokens.
        uint256 cTokensMinted = cToken.balanceOf(address(this));

        uint256 _cherryRate;
        _cherryRate = exchangeRate();

        // mint CherryDai to liquidity provider
        uint256 cherryDaiToMint = _amount.mul(1e18).div(_cherryRate);
        cherryDai.mint(msg.sender, cherryDaiToMint);

        // internal accounting to store pool balances
        poolBalance = poolBalance.add(_amount);
        poolcBalance = cTokensMinted;
        longPoolBalance = longPoolBalance.add(_amount.div(2));
        shortPoolBalance = shortPoolBalance.add(_amount.div(2));

        emit DepositLiquidity(msg.sender, _amount);

        emit MintCherry(msg.sender, _amount, cTokensMinted, cherryDaiToMint);

        return cherryDaiToMint;
    }

    /**
     * @notice Get long pool utilization
     * @param _longPoolReserved amount of liquidity reserved in the long pool
     * @return current long pool utilization as a decimal scaled 10*18
     */
    function calcLongPoolUtil(uint256 _longPoolReserved) public view returns (uint256) {
        return (_longPoolReserved * 1e18) / longPoolBalance;
    }

    /**
     * @notice Get short pool utilization
     * @param _shortPoolReserved amount of liquidity reserved in the short pool
     * @return current short pool utilization as a decimal scaled 10*18
     */
    function calcShortPoolUtil(uint256 _shortPoolReserved) public view returns (uint256) {
        return (_shortPoolReserved * 1e18) / shortPoolBalance;
    }

    /**
     * @notice Get Cherrydai balance for liquidity provider
     * @param _provider liquidity provider address
     * @return CherryDai balance
     */
    function cherryDaiBalanceOf(address _provider) public view returns (uint256) {
        return cherryDai.balanceOf(_provider);
    }

    /**
     * @notice transfer underlying asset back to liquidity provider assuming pool liquidity is still sufficient.
     * @dev the amount returned is the number of cherrytokens multiplied by the current exchange rate
     * The sender should approve the _amount to this contract address
     * @param _amount amount of CherryDai to redeem
     * @return daiRedeemed amount of DAI redeemed
     */
    function redeem(uint256 _amount) external isLongUtilized() isShortUtilized() returns (uint256) {
        require(
            _amount <= cherryDai.balanceOf(msg.sender),
            "CherryPool::redeem request is more than current token balance"
        );

        // get exchange rate from Cherrydai to Dai+fee
        uint256 _cherryRate;
        _cherryRate = exchangeRate();

        uint256 daiRedeemed = _amount.mul(_cherryRate).div(1e18);

        require(getCashPrior() < daiRedeemed, "Redeem:insufficient cash");

        // pay the message.sender the daiRedeemed amount and burn their _amount of CherryDai
        payout(msg.sender, daiRedeemed, _amount);

        emit RedeemCherry(msg.sender, _amount);

        return daiRedeemed;
    }

    /**
     * @notice Get available pool balance (total pool balance - total reserved balance)
     * @return available pool balance
     */
    function getCashPrior() internal returns (uint256) {
        return poolBalance.sub((shortPoolReserved.add(longPoolReserved)));
    }

    /**
     * @notice Transfer the underlying asset
     * @param _redeemer redeemer address
     * @param _redeemedDaiAmount amount of DAI to transfer
     * @param _redeemedCherryDaiTokens amount of CherryDAI to burn
     */
    function payout(address _redeemer, uint256 _redeemedDaiAmount, uint256 _redeemedCherryDaiTokens) internal {
        // Remove the CherryDai from the supply
        cherryDai.burnFrom(_redeemer, _redeemedCherryDaiTokens);

        // redeem an amount of underlying by sending cDai to compound in exchange for Dai.
        require(cToken.redeemUnderlying(_redeemedDaiAmount) == 0, "CherryPool::payout - something went wrong");

        // transfer Dai to redeemer.
        token.transfer(_redeemer, _redeemedDaiAmount);

        emit TransferDai(_redeemer, _redeemedDaiAmount);
    }

    /**
     * @notice the rate of CherryDai redeemable for Dai.
     * @dev Each CherryDai is convertible into the underlying asset + the fees accrued through liquidity provision.
     * @return rate Exchange rate
     */
    function exchangeRate() public returns (uint256) {
        uint256 rate;
        if(cherryDai.totalSupply() == 0) {
            rate = 1;
        }
        else {
            rate = (uint256(int256(poolcBalance) + poolcTokenProfit).mul(getcTokenExchangeRate())).div(cherryDai.totalSupply());
        }

        emit CurrentExchangeRate(uint256(rate));

        return uint256(rate);
    }

    /**
     * @notice Set CherryDai token address
     * @dev can only be called by the owner
     * @param _token CherryDai token address
     */
    function setToken(address _token) external {
        require(msg.sender == owner, "Cherrypool::not authorized to call function");

        cherryDai = CherryDai(_token);

        emit SetCherryDai(_token);
    }

    function _reserveLongPool(uint256 _amount) internal canReserveLong(_amount) {
        require(_amount > 0, "Cherrypool::invalid amount to reserve");

        longPoolReserved = longPoolReserved.add(_amount);
    }

    function _reserveShortPool(uint256 _amount) internal canReserveShort(_amount) {
        require(_amount > 0, "Cherrypool::invalid amount to reserve");

        shortPoolReserved = shortPoolReserved.add(_amount);
    }

    function _freeLongPool(uint256 _amount) internal {
        require(_amount > 0, "Cherrypool::invalid amount to free");
        longPoolReserved.sub(_amount);

        emit FreeLongPool(_amount);
    }

    function _freeShortPool(uint256 _amount) internal {
        require(_amount > 0, "Cherrypool::invalid amount to free");
        shortPoolReserved.sub(_amount);

        emit FreeShortPool(_amount);
    }

    function _addcTokenPoolProfit(int256 _profit) internal {
        poolcTokenProfit += _profit;
    }

    function getcTokenExchangeRate() public view returns (uint256) {
        return cToken.exchangeRateStored();
    }

}
