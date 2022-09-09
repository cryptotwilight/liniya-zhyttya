// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
/**
 * This is the Liniya Zhyttya contract. It's purpose is to enable distressed users to request anonymous assistance from the world.
 * This contract will coordinate the listing, payment, fulfilment and confirmation of relief requests. 
 * The service will check that products are verified prior to listing.
 */
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/6a8d977d2248cf1c115497fccfd7a2da3f86a58f/contracts/token/ERC20/IERC20.sol"; 
import "https://github.com/Block-Star-Logic/open-version/blob/e161e8a2133fbeae14c45f1c3985c0a60f9a0e54/blockchain_ethereum/solidity/V1/interfaces/IOpenVersion.sol";
import "https://github.com/Block-Star-Logic/open-libraries/blob/703b21257790c56a61cd0f3d9de3187a9012e2b3/blockchain_ethereum/solidity/V1/libraries/LOpenUtilities.sol";
import "https://github.com/Block-Star-Logic/open-product/blob/5e429338bf1f269d3669bcf5446661d4a2d9d6ad/blockchain_ethereum/solidity/V1/interfaces/IOpenProduct.sol";
import "https://github.com/Block-Star-Logic/open-product/blob/5e429338bf1f269d3669bcf5446661d4a2d9d6ad/blockchain_ethereum/solidity/V1/interfaces/IOpenProductCore.sol";

import "./ILiniyaZhyttya.sol";

contract LiniyaZhytta is ILiniyaZhyttya, IOpenVersion {

    using LOpenUtilities for uint256; 

    address NATIVE                      = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; 
    string REQUESTED_STATUS             = "REQUESTED";
    string PAID_STATUS                  = "PAID";
    string IN_FULFILLMENT_STATUS        = "IN_FULFILLMENT";
    string DELIVERED_STATUS             = "DELIVERED";
    string DELIVERY_CONFIRMED_STATUS    = "CONFIRMED";

    address administrator; 
    address self; 
    IERC20 stakeErc20; 
    IOpenProductCore productManager; 

    string name = "LINIYA ZHYTTYA CORE"; 
    uint256 version = 2; 

    uint256 stakeAmount; 
    mapping(address=>mapping(uint256=>uint256)) stakedAmountByRefByServiceProvider; 

    Ref [] refs; 

    mapping(uint256=>Ref) refById; 
    mapping(address=>uint256[]) refIdsByCreator; 
    mapping(uint256=>string[]) statiByRef; 
    mapping(uint256=>mapping(string=>uint256)) timeByStatusByRef; 
    mapping(uint256=>mapping(string=>address)) modifierByStatusByRef; 
    mapping(string=>uint256[]) refsByStatus; 

    mapping(address=>uint256[]) modifiedRefsByAddress; 

    mapping(uint256=>uint256) paidValueByRef;

    constructor(address _admin, address openProductCoreAddress, uint256 _stakeAmount, address _erc20) {
        administrator = _admin; 
        self = address(this);
        stakeAmount = _stakeAmount; 
        stakeErc20 = IERC20(_erc20);
        productManager = IOpenProductCore(openProductCoreAddress);
    }

    function getName() view external returns (string memory _name) {
        return name; 
    }

    function getVersion() view external returns (uint256 _version) {
        return version; 
    }

    function getStakeAmount() view external returns (uint256 _stakeAmount, address _erc20) {
        return (stakeAmount, address(stakeErc20));
    }

    function getRefs() view external returns (Ref [] memory _refs){
        return refs; 
    }

    function getMyRefs() view external returns (Ref [] memory _refs){
        uint256 [] memory creatorRefs_ = refIdsByCreator[msg.sender];
        return getRefArray(creatorRefs_);
    }

    function getModifiedRefs() view external returns (Ref [] memory _refs){
        return getRefArray(modifiedRefsByAddress[msg.sender]);
    }

    function getRefHistory(uint256 _ref) view external returns (string[] memory _statuses, uint256 [] memory _dates, address [] memory _modifier){
        string [] memory statuses_ = statiByRef[_ref];
        _dates = new uint256[](statuses_.length);
        for(uint256 x = 0; x < _dates.length; x++){
            _dates[x] = timeByStatusByRef[_ref][statuses_[x]];
            _modifier[x] = modifierByStatusByRef[_ref][statuses_[x]];
        }
        return (statuses_, _dates, _modifier);
    }

    function getRefs(string memory _status) view external returns (Ref [] memory _refs){
        return getRefArray(refsByStatus[_status]);
    }

    function requestReliefProduct(uint256 _lat, uint256 _long, address _reliefProduct, uint256 _quantity) external returns (Ref memory  _requestRef){
        require(productManager.isVerified(_reliefProduct), " unknown product ");
        Ref memory ref_ = Ref({
                                id : block.timestamp, 
                                createDate : block.timestamp, 
                                product  : _reliefProduct,
                                quantity  : _quantity, 
                                lat : _lat, 
                                long : _long, 
                                status : REQUESTED_STATUS,
                                creator : msg.sender,   
                                serviceProvider : address(0)
                            });
        refs.push(ref_);
        refById[ref_.id] = ref_; 
        refIdsByCreator[msg.sender].push(ref_.id); 
        updateStatus(ref_.id, REQUESTED_STATUS);
        statiByRef[ref_.id].push(REQUESTED_STATUS); 
        return ref_;  
    }

    function buyReliefProduct(uint256 _ref, uint256 _quantity) payable external returns (uint256 _purchaseTime){
        Ref storage ref_ = refById[_ref];
        require(ref_.quantity == _quantity, " request <-> buy quantity mis-match");
        IOpenProduct product_ = IOpenProduct(ref_.product);
        address erc20Addreess_ = product_.getErc20(); 
        uint256 value_ = _quantity * product_.getPrice(); 
        if(erc20Addreess_ == NATIVE){
            require(msg.value >= value_, "insufficient value transmitted");
        }
        else {
            IERC20 erc20_ = IERC20(erc20Addreess_);
            erc20_.transferFrom(msg.sender, self, value_); 
            paidValueByRef[_ref] = value_;       
        }
        _purchaseTime = block.timestamp; 
        updateStatus(ref_.id, PAID_STATUS);

        return _purchaseTime; 
    }

    function claimDelivery(uint256 _ref, uint256 _stakeAmount) external returns (uint256 _claimTime) {
        require(_stakeAmount >= stakeAmount, " insufficient amount staked ");
        address serviceProvider = msg.sender;
        stake(_ref);

        Ref storage ref_ = refById[_ref];
        ref_.status = IN_FULFILLMENT_STATUS; 
        ref_.serviceProvider = serviceProvider; 
        _claimTime = block.timestamp; 
        return _claimTime; 
    }


    function deliverReliefProduct(uint256 _lat, uint256 _long, uint256 _quantity, uint256 _ref) external returns (uint256 _deliveryTime){
        Ref storage ref_ = refById[_ref];
        require(_lat == ref_.lat && _long == ref_.long, " coordinates mis match ");
        require(ref_.quantity == _quantity, " request <-> deliver quantity mis-match ");
        ref_.status = DELIVERED_STATUS;
        updateStatus(_ref, DELIVERED_STATUS);
        _deliveryTime = block.timestamp; 
        return _deliveryTime; 
    }

    function confirmReliefDelivery(uint256 _ref, uint256 _lat, uint256 _long) external returns (uint256 _confirmationTime){
        Ref storage ref_ = refById[_ref];
        require(_lat == ref_.lat && _long == ref_.long, " coordinates mis match ");
        ref_.status = DELIVERY_CONFIRMED_STATUS;
        updateStatus(_ref, DELIVERY_CONFIRMED_STATUS);
        unstake(ref_.id, ref_.serviceProvider);
        payout(_ref);
        _confirmationTime = block.timestamp; 
        return _confirmationTime; 
    }

    function setStakeAmount(uint256 _amount) external returns (bool) {
        require(msg.sender == administrator, " admin only ");
        stakeAmount = _amount; 
        return true; 
    }


    // ==================================== INTERNAL =============================================================

    function payout(uint256 _ref) internal returns (bool _paidOut) {
        uint256 value_ = paidValueByRef[_ref];
        Ref storage ref_ = refById[_ref];
        IOpenProduct product_ = IOpenProduct(ref_.product);
        address erc20Addreess_ = product_.getErc20(); 
        if(erc20Addreess_ == NATIVE){
            address payable sp = payable(ref_.serviceProvider);
            sp.transfer(value_);
        }
        else {
            IERC20 erc20_ = IERC20(erc20Addreess_);
            erc20_.transfer(ref_.serviceProvider, value_);        
        }
        return true; 
    }

    function stake(uint256 _ref) internal returns (bool _staked) {
        stakeErc20.transferFrom(msg.sender, self, stakeAmount);
        stakedAmountByRefByServiceProvider[msg.sender][_ref] = stakeAmount; 
        return true; 
    }

    function unstake(uint256 _ref, address _staker) internal returns (bool _unstaked) {
        uint256 stakeAmount_ = stakedAmountByRefByServiceProvider[_staker][_ref];
        stakeErc20.transfer(_staker, stakeAmount_);
        return true; 
    }

    function updateStatus(uint256 _ref, string memory _status) internal returns (bool _updated) {
        string [] memory stati = statiByRef[_ref];
        if(stati.length >= 1){
            string memory latestStatus_ = stati[stati.length-1];
            uint256 [] memory refs_ = refsByStatus[latestStatus_];
            refsByStatus[latestStatus_] = _ref.remove(refs_);
        }
        statiByRef[_ref].push(_status); 
        timeByStatusByRef[_ref][_status] = block.timestamp; 
        modifierByStatusByRef[_ref][_status] = msg.sender; 
        refsByStatus[_status].push(_ref); 
        modifiedRefsByAddress[msg.sender].push(_ref);  
        return true; 
    }


    function getRefArray(uint256 [] memory _ids) view internal returns (Ref[] memory _refs) {
        _refs = new Ref[](_ids.length);
        for(uint256 x = 0; x < _ids.length; x++){
            _refs[x] = refById[_ids[x]]; 
        }
        return _refs; 
    }

}