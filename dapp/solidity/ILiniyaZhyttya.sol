// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

interface ILiniyaZhyttya { 

    struct Ref { 
        uint256 id; 
        uint256 createDate; 
        address product;
        uint256 quantity; 
        uint256 lat; 
        uint256 long; 
        string status; 
        address creator; 
        address serviceProvider; 
    }

    function getRefs() view external returns (Ref [] memory _refs);

    function getMyRefs() view external returns (Ref [] memory _refs);

    function getModifiedRefs() view external returns (Ref [] memory _refs);

    function getRefHistory(uint256 _refId) view external returns (string[] memory _status, uint256 [] memory _date, address [] memory _modifier);

    function getRefs(string memory _status) view external returns (Ref [] memory _refs);

    function requestReliefProduct(uint256 _lat, uint256 _long, address _reliefProduct, uint256 _quantity) external returns (Ref memory  _requestRef);

    function buyReliefProduct(uint256 _refId, uint256 _quantity) payable external returns (uint256 _purchaseTime);

    function deliverReliefProduct(uint256 _lat, uint256 _long, uint256 _amount, uint256 _refId) external returns (uint256 _deliveryTime);

    function confirmReliefDelivery(uint256 _refId, uint256 _lat, uint256 _long) external returns (uint256 _confirmationTime);
}