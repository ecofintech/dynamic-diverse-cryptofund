// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.8;

/**
  *  Based on original Lescovex CIF design and OpenZeppelin
  *  libraries. Aggregations, upgrades and security revisions
  *  by Ecofintech Coop.
  *  https://ecofintech.coop
**/

library SafeMath {
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
      if (a == 0) {
          return 0;
      }
      uint256 c = a * b;
      require(c / a == b, "SafeMath: multiplication overflow");
      return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
      return div(a, b, "SafeMath: division by zero");
  }

  function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
      require(b > 0, errorMessage);
      uint256 c = a / b;
      return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
      return sub(a, b, "SafeMath: subtraction overflow");
  }

  function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
      require(b <= a, errorMessage);
      uint256 c = a - b;
      return c;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) {
      uint256 c = a + b;
      require(c >= a, "SafeMath: addition overflow");
      return c;
  }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        // silence state mutability warning without generating bytecode
        this;
        return msg.data;
    }
}

contract OwnableContract is Context {
      address internal owner;
      event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
      constructor () internal {
          address msgSender = _msgSender();
          owner = msgSender;
          emit OwnershipTransferred(address(0), msgSender);
      }

      modifier onlyOwner() {
          require(owner == _msgSender(), "Ownable: caller is not the owner");
          _;
      }

      function getOwner() public view returns (address) {
          return owner;
      }

      function transferOwnership(address newOwner) public virtual onlyOwner {
          require(newOwner != address(0), "Ownable: new owner is the zero address");
          emit OwnershipTransferred(owner, newOwner);
          owner = newOwner;
      }
}

//////////////////////////////////////////////////////////////
//                                                          //
//                 Open End Crypto Fund                     //
//                                                          //
//////////////////////////////////////////////////////////////

contract Dynamic_RRC20 is OwnableContract {

    using SafeMath for uint256;

    mapping (address => uint256) public balances;
    mapping (address => uint256) public requestWithdraws;
    mapping (address => mapping (address => uint256)) internal allowed;
    mapping (address => timeHold) holded;
    struct timeHold{
        uint256[] amount;
        uint256[] time;
        uint256 length;
    }

    string public constant standard = "RRC-20 Open End Cryptoinvestment Fund";
    // Hardcoded to be a constant
    uint8 public constant decimals = 8;
    uint256 public totalSupply;
    string public name;
    string public symbol;
    uint256 public holdTime;
    uint256 public holdMax;
    uint256 public maxSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function tokenBalanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    function tokenHoldedOf(address _owner, uint256 n) public view returns (uint256) {
        return holded[_owner].amount[n];
    }

    function hold(address _to, uint256 _value) internal {
        holded[_to].amount.push(_value);
        holded[_to].time.push(block.number);
        holded[_to].length++;
    }

    function transfer(address _to, uint256 _value) public returns (bool) {
        require(_to != address(0));
        require(_value <= balances[msg.sender]);
        // SafeMath.sub will throw if there is not enough balance.
        balances[msg.sender] = balances[msg.sender].sub(_value);
        delete holded[msg.sender];
		hold(msg.sender, balances[msg.sender]);
        hold(_to,_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
        require(_to != address(0));
        require(_value <= balances[_from]);
        require(_value <= allowed[_from][msg.sender]);
        balances[_from] = balances[_from].sub(_value);
        delete holded[_from];
		hold(_from, balances[_from]);
        hold(_to,_value);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowed[_owner][_spender];
    }

    function increaseApproval(address _spender, uint _addedValue) public returns (bool) {
        allowed[msg.sender][_spender] = allowed[msg.sender][_spender].add(_addedValue);
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }

    function decreaseApproval(address _spender, uint _subtractedValue) public returns (bool) {
        uint oldValue = allowed[msg.sender][_spender];
        if (_subtractedValue > oldValue) {
            allowed[msg.sender][_spender] = 0;
        } else {
            allowed[msg.sender][_spender] = oldValue.sub(_subtractedValue);
        }
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }

    function approveAndCall(address _spender, uint256 _value, bytes memory _extraData) public returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);

        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, address(this), _extraData);
            return true;
        }
    }
}

interface tokenRecipient {
    function receiveApproval(address _from, uint256 _value, address _token, bytes calldata _extraData) external ;
}

contract DynamicCryptoFund is Dynamic_RRC20 {

    uint256 public tokenPrice = 0;
    // constant to simplify conversion of token amounts into integer form
    uint256 public tokenUnit = uint256(10)**decimals;
    uint256 public contractBalance = 0;
    mapping(address => uint256) internal funds;


    event LogDeposit(address sender, uint amount);
    event LogWithdrawal(address receiver, uint amount);
    event requestedWithdrawal(address sender, uint value);
    event variationPrice(uint256 value);

    constructor(uint256 initialSupply, uint256 contractHoldTime, uint256 contractHoldMax, uint256 contractMaxSupply, address contractOwner) public {
        name = "Dynamic Diverse Crypto Fund";
        symbol = "D2";
        totalSupply = initialSupply;
        holdTime = contractHoldTime;
        holdMax = contractHoldMax;
        maxSupply = contractMaxSupply;
        owner = msg.sender;
        balances[contractOwner] = balances[contractOwner].add(totalSupply);
    }


/*
    function cryptoFund( 
            uint256 initialSupply,
            string memory contractName,
            string memory tokenSymbol,
            uint256 contractHoldTime,
            uint256 contractHoldMax,
            uint256 contractMaxSupply,
            address contractOwner

        ) public {

        totalSupply = initialSupply;
        name = contractName;
        symbol = tokenSymbol;
        holdTime = contractHoldTime;
        holdMax = contractHoldMax;
        maxSupply = contractMaxSupply;
        owner = contractOwner;
        balances[contractOwner] = balances[contractOwner].add(totalSupply);
    }
*/
    receive() external payable {
        buy();
        contractBalance = address(this).balance;
    }

    function depositFunds() external payable onlyOwner returns(bool success) {
        // Check for overflows;
        assert(address(this).balance + msg.value >= address(this).balance);
        contractBalance = address(this).balance;
        emit LogDeposit(msg.sender, msg.value);
        return true;
    }

    function withdrawReward() external {
        uint i = 0;
        uint256 ethAmount = 0;
        uint256 len = holded[msg.sender].length;
        while (i <= len - 1){
            if (block.number -  holded[msg.sender].time[i] > holdTime && block.number -  holded[msg.sender].time[i] < holdMax){
                ethAmount += tokenPrice * holded[msg.sender].amount[i];
            }
            i++;
        }
        require(ethAmount > 0);
        require(ethAmount>=(tokenPrice*requestWithdraws[msg.sender]));
        emit LogWithdrawal(msg.sender, ethAmount);
        totalSupply = totalSupply.sub(requestWithdraws[msg.sender]);
        balances[msg.sender] = balances[msg.sender].sub(requestWithdraws[msg.sender]);
        contractBalance = address(this).balance.sub(ethAmount);
        emit Transfer(msg.sender, address(this), requestWithdraws[msg.sender]);
        delete holded[msg.sender];
        hold(msg.sender,balances[msg.sender]);
        msg.sender.transfer(tokenPrice*requestWithdraws[msg.sender]/tokenUnit);
    }

    function setPrice(uint256 _value) public onlyOwner {
      tokenPrice = _value;
      emit variationPrice(_value);
    }

//    function getPrice() public view returns (uint256 _value) {
//        return tokenPrice;
//    }

    function requestWithdraw(uint value) public {
      require(value <= balances[msg.sender]);
      delete holded[msg.sender];
      hold(msg.sender, value);
      requestWithdraws[msg.sender]=value;
      emit requestedWithdrawal(msg.sender, value);
    }


    function buy() public payable {
        require(totalSupply <= maxSupply);
        require(msg.value > 0);
        uint256 tokenAmount = (msg.value * tokenUnit) / tokenPrice ;
        contractBalance = address(this).balance;
        transferBuy(msg.sender, tokenAmount);
    }

    function transferBuy(address _to, uint256 _value) internal returns (bool) {
        require(_to != address(0));
        // SafeMath.add will throw if there is not enough balance.
        totalSupply = totalSupply.add(_value);
        hold(_to,_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(address(this), _to, _value);
        return true;
    }


    function withdrawFunds(uint _value) external onlyOwner returns(bool success) {
        require(msg.sender == owner);
        assert(address(this).balance + _value >= address(this).balance);
        // Reentrancy guard
//        uint fund = funds[msg.sender];
        uint fund = address(this).balance;
//        funds[msg.sender] = 0;
        contractBalance = address(this).balance;

        msg.sender.transfer(fund);
        
        return true;
    }
}


/*
to do:
pending withdraws - num de withdraws a l espera

*/