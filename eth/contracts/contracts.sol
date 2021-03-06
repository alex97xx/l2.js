pragma solidity ^0.4.19;

contract XPaymentChannel {
    address public A;
    address public B;
    mapping( address=> uint256) values;
    uint256 public sum;
    uint256 public mv;

    uint256 challenge_endtime;
    uint32 nonce;

    enum ChannelState{init,funded,challenge,finished}
    ChannelState public state;

    uint256 ttl;

    uint256 public constant challenge_period = 1 minutes;

    event OnPayment(address sender, uint256 value);
    event OnChallengeStart(address sender,uint32 id,uint256 vA, uint256 vB,uint8 v,bytes32 r,bytes32 s);
    event OnChallengeUpdate(address sender,uint32 id,uint256 vA, uint256 vB,uint8 v,bytes32 r,bytes32 s);
    event OnChallengePenalty(address sender,uint32 id,uint256 vA, uint256 vB,uint8 v,bytes32 r,bytes32 s);
    event OnChallengeFinish(address sender,uint32 id,uint256 vA, uint256 vB,uint8 v,bytes32 r,bytes32 s);
    event OnWithdraw(address sender, uint256 value);

    function XPaymentChannel(address _B, uint256 _ttl, uint256 _mv) payable public {
    	A=msg.sender;
    	B=_B;
    	ttl = now+_ttl;
    	challenge_endtime = 0;
    	nonce = 0;
    	mv = _mv;
    	require(msg.value>=mv);
    	if(msg.value>0){
    		values[msg.sender]=msg.value;	
    		state=ChannelState.funded;
    		sum=msg.value;
    	} else {
    		sum=0;
    		state=ChannelState.init;
    	}
    }

	function ChannelInfo() public view returns(
		address,address, uint256,uint256, uint256,uint32,uint8,uint256){
		return (A,B,values[A],values[B],challenge_endtime,nonce,uint8(state),ttl);
	}

	function () payable public {
		require(msg.sender==A ||msg.sender==B);
    	require(msg.value>=mv);
		require(msg.value>0);
		values[msg.sender]+=msg.value;
    	if(state==ChannelState.init)state=ChannelState.funded;
		sum+=msg.value;
		emit OnPayment(msg.sender,msg.value);
	}

	function balance() public view returns(uint256){
		return sum;
	}


	function valueX(address addr) public view returns(uint256){
		return values[addr];
	}

	function checkSig(uint32 id,uint256 vA, uint256 vB,uint256 h,
		uint8 v,bytes32 r,bytes32 s) view internal {
		if(msg.sender==A){
			require(B == ecrecover(keccak256(address(this), A, id,vA,vB), v, r, s));
		} else if(msg.sender==B){
			require(A == ecrecover(keccak256(address(this), B, id,vA,vB), v, r, s));
		} else {
			revert();
		}	
	}

	function testSig(uint32 id,uint256 vA, uint256 vB,uint256 h,bytes pi,
		uint8 v,bytes32 r,bytes32 s) view public returns(bool){
		//if(h!=0){require(h==uint256(keccak256(pi)));}
		checkSig(id,vA,vB,h,v,r,s);
		return true;
	}	

	function testHL(uint256 h, bytes pi) pure public returns(uint256,bool){
		uint256 x=uint256(keccak256(pi));
		if(h!=0){require(h==uint256(keccak256(pi)));}
		return (x,x==h);
	}	


	function challengeStart(uint32 id,uint256 vA, uint256 vB,uint256 h, bytes pi,
		uint8 v,bytes32 r,bytes32 s) public{
    	require(state==ChannelState.funded);
		require(sum>0 && sum == vA+vB);
		if(h!=0){require(h==uint256(keccak256(pi)));}
		checkSig(id,vA,vB,h,v,r,s);
		require(id>nonce);
		nonce=id;
		challenge_endtime = now + challenge_period;
		state=ChannelState.challenge;
		emit OnChallengeStart(msg.sender,id,vA,vB,v,r,s);
	}

	function challengeUpdate(uint32 id,uint256 vA, uint256 vB,uint256 h, uint256 pi,
		uint8 v,bytes32 r,bytes32 s) public{
    	require(state==ChannelState.challenge);
		require(sum>0 && sum == vA+vB);
		if(h!=0){require(h==uint256(keccak256(pi)));}
		checkSig(id,vA,vB,h,v,r,s);
		require(id>nonce);
		nonce=id;
		emit OnChallengeUpdate(msg.sender,id,vA,vB,v,r,s);
	}

	function challengePenalty(uint32 id,uint256 vA, uint256 vB,uint256 h, uint256 pi,
		uint8 v,bytes32 r,bytes32 s) public{
    	require(state==ChannelState.challenge);
		require(sum>0 && sum == vA+vB);
		if(h!=0){require(h==uint256(keccak256(pi)));}
		checkSig(id,vA,vB,h,v,r,s);
		require(id>nonce);
		nonce=id;
		msg.sender.transfer(sum);
		values[A]=0;
		values[B]=0;
		sum=0;
		state=ChannelState.finished;
		emit OnChallengePenalty(msg.sender,id,vA,vB,v,r,s);
	}

	function challengeFinish(uint32 id,uint256 vA, uint256 vB,uint256 h, uint256 pi,
		uint8 v,bytes32 r,bytes32 s) public{
    	require(state==ChannelState.challenge);
    	require(now>challenge_endtime);
		require(sum>0 && sum == vA+vB);
		if(h!=0){require(h==uint256(keccak256(pi)));}
		checkSig(id,vA,vB,h,v,r,s);
		require(id==nonce);
		if(vA>0)A.transfer(vA);
		if(vB>0)B.transfer(vB);
		values[A]=0;
		values[B]=0;
		sum=0;
		state=ChannelState.finished;
		emit OnChallengeFinish(msg.sender,id,vA,vB,v,r,s);
	}


	function withdraw() public{
		require(state!=ChannelState.finished);
		uint256 value = values[msg.sender];
		require(value>0);
		require(now>ttl);		
		msg.sender.transfer(value);
		sum-=value;
		values[msg.sender]=0;
		emit OnWithdraw(msg.sender,value);
	}
	
}


