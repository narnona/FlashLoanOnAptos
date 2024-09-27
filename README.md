## 基于Hot Potato模式实现对FA标准资产的闪电贷

### 1. 背景：

在以太坊的EVM中可以进行动态调用，即一个合约中可通过传入的参数来决定调用哪个合约进行执行。而在Aptos的Move虚拟机中，为了安全并没有实现动态调用的功能，合约所有的执行路径在编译时就已经确定了。那么，对于该情况，如何实现闪电贷功能呢？答案是，使用Hot Potato模式可以实现。

<br>

### 2. 原理：

根据Move面向资源编程的特点，Hot Potato模式以资源为关键。通过给调用**闪电贷的贷款函数**的合约返回一个没有任何ability（即没有copy/store/drop/key）的struct，如果该合约不销毁该struct，则不会成功结束执行，同时该合约仅靠本身无法对该struct进行删除。只能通过调用**闪电贷的还贷函数**帮助销毁，这就意味着必须进行还贷。总的来说就是，通过该无能力的struct，将贷款函数和还贷函数必然地连接起来，从而实现闪电贷。

<br>

### 3. 实现：

本项目对上面的原理实现了对Fungible Asset资产进行闪电贷的逻辑，同时对功能进行了适当的扩充。功能有：

- 对于合约管理者：可调用`addTokenType()`添加不同的可质押和闪电贷的FA资产；
- 对于普通用户：可调用`stake()`和`unstake()`添加质押和移除质押；
- 对于闪贷者：可在合约中调用`flashloan()`和`reply()`来进行闪电贷；

view接口：

- `get_FACoinItem_object_address(faCoin_addr)`：获取存储该代币资产的Object的地址；
- `get_UserStake(faCoin_addr)`：获取该代币资产的用户质押情况；
  
<br>

### 4. 结果：

该闪电贷合约已发布到testnet的object上：`0xee0adabd12721e8b28ca9616d4410a765f175b209748cb87ce86a389fc47b5d0`

<br>

目前已添加的FA资产地址：

Flash Coin：`0xf75b2c73f22fa9c1ebc49506dded56dd8aabb719261c8706f7f3b5a321fa3f29`

FA Coin：`0xfedcac427cbfd4676eefae4a524f3ab210d3f8923bd7d61067532bf45f0a6a68`

<br>

项目中的User目录是进行闪贷的合约示例，其已发布到：`0xe9daa4331018373a7d1c4ee797dc9a4348ac9e9564e30f99e68e22acd1913bd5`















