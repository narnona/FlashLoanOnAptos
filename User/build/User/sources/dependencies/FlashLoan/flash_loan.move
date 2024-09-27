module FlashLoan::flash_loan {
    use std::bcs;
    use std::signer;
    use aptos_std::table::{Self, Table};
    use aptos_std::string_utils;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::object::{Self, Object, ObjectCore};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::Metadata;

    // ================================= Errors ================================= //
    /// Error code indicating that the sender is not the owner of the object
    const ERR_NOT_OWNER: u64 = 1;
    /// Error code indicating that the FACoin type not exist
    const ERR_NOT_EXIST_FACOIN_TYPE: u64 = 2;
    /// Error code indicating that Exceeding the stake amount
    const ERR_EXCEED_STAKE_AMOUNT: u64 = 3;
    /// Error code indicating that already existed
    const ERR_EXISTED: u64 = 4;

    // the key of FlashLoan
    struct HotPotato { }

    struct Receipt has key, store {
        metadata: Object<Metadata>,
        amount: u64
    }

    // Store user stake information, Table for FACoin, SimpleMap for user
    struct UserStake has key {
        stake_table: Table<address, SimpleMap<address, u64>>
    }

    // Use to generate FACoinPool Object signer
    struct FACoinPoolController has key {
        extend_ref: object::ExtendRef
    }

    // Store all FACoinItem Object ExtendRef
    struct FACoinItemController has key {
        ControllerList: Table<address, object::ExtendRef>
    }

    fun init_module(admin: &signer) {
        // init UserStake
        move_to(admin, UserStake { 
            stake_table: table::new<address, SimpleMap<address, u64>>()
        });

        // generate FACoinPool Object and store
        let faCoinPool_constructor_ref = object::create_object(signer::address_of(admin));
        let faCoinPool_signer = object::generate_signer(&faCoinPool_constructor_ref);
        move_to(admin, FACoinPoolController {
            extend_ref: object::generate_extend_ref(&faCoinPool_constructor_ref)
        });

        // init FACoinItemController
        move_to(&faCoinPool_signer, FACoinItemController{
            ControllerList: table::new<address, object::ExtendRef>()
        })
    }

    // ======================== Write functions ========================
    // add staking token type (used by module admin)
    public entry fun addTokenType(sender: &signer, faCoin_addr: address) acquires UserStake, FACoinItemController, FACoinPoolController {
        // Is it the owner of the object
        assert!(object::is_owner(object::address_to_object<ObjectCore>(@FlashLoan), signer::address_of(sender)), ERR_NOT_OWNER);
        
        // Check if the token address already has an Object
        let faCoinPool_addr = signer::address_of(&generate_FACoinPool_signer());
        let faCoin_addr_to_Item_addr = get_FACoinItem_object_address(faCoin_addr);
        assert!(!object::is_object(faCoin_addr_to_Item_addr), ERR_EXISTED);

        // generate FACoinItem Object
        let faCoinItem_constructor_ref = object::create_named_object(
            &generate_FACoinPool_signer(),
            construct_FACoinItem_seed(faCoin_addr)
        );
        let faCoinItem_Extend_ref = object::generate_extend_ref(&faCoinItem_constructor_ref);
        table::add(
            &mut borrow_global_mut<FACoinItemController>(faCoinPool_addr).ControllerList, 
            faCoin_addr, 
            faCoinItem_Extend_ref
        );

        // update UserStake
        table::add(
            &mut borrow_global_mut<UserStake>(@FlashLoan).stake_table, 
            faCoin_addr, 
            simple_map::new<address, u64>()
        );
    }

    // user stake FACoin
    public entry fun stake(user: &signer, faCoin_addr: address, amount: u64)
        acquires UserStake, FACoinPoolController
    {
        // Check if the FACoinItem Object is exist
        let faCoin_addr_to_Item_addr = get_FACoinItem_object_address(faCoin_addr);
        assert!(object::is_object(faCoin_addr_to_Item_addr), ERR_NOT_EXIST_FACOIN_TYPE);

        // transfer 
        primary_fungible_store::transfer(
            user,
            get_Metadata(faCoin_addr),
            faCoin_addr_to_Item_addr,
            amount
        );

        // update UserStake
        let stake_amount = get_user_stake_amount(faCoin_addr, signer::address_of(user));
        update_user_stake_amount(faCoin_addr, signer::address_of(user), stake_amount + amount);
    }

    // user unstake FACoin
    public entry fun unstake(user: &signer, faCoin_addr: address, amount: u64)
        acquires UserStake, FACoinItemController, FACoinPoolController
    {
        // Check if FACoinItem Object is exist
        // let faCoinPool_addr = signer::address_of(&generate_FACoinPool_signer());
        let faCoin_addr_to_Item_addr = get_FACoinItem_object_address(faCoin_addr);
        assert!(object::is_object(faCoin_addr_to_Item_addr), ERR_NOT_EXIST_FACOIN_TYPE);

        // get FACoinItem Object signer
        let faCoinItem_signer = get_FACoinItem_object_signer(faCoin_addr);

        // get user stake amount
        let stake_amount = get_user_stake_amount(faCoin_addr, signer::address_of(user));

        // check 
        assert!(stake_amount >= amount, ERR_EXCEED_STAKE_AMOUNT);

        // transfer
        primary_fungible_store::transfer(
            &faCoinItem_signer,
            get_Metadata(faCoin_addr),
            signer::address_of(user),
            amount
        );

        // update UserStake
        update_user_stake_amount(faCoin_addr, signer::address_of(user), stake_amount - amount);
    }

    // Flash loan
    public fun flashLoan(lender: &signer, faCoin_addr: address, amount: u64): (Receipt, HotPotato)
        acquires FACoinItemController, FACoinPoolController
    {
        let metadata = get_Metadata(faCoin_addr);
        
        // Save the amount and metadata in the Receipt
        let receipt = Receipt {
            metadata,
            amount
        };

        // get FACoinItem Object signer
        let faCoinItem_signer = get_FACoinItem_object_signer(faCoin_addr);

        // Transfer the FACoins to the lender
        primary_fungible_store::transfer(
            &faCoinItem_signer,
            metadata,
            signer::address_of(lender),
            amount
        );

        // Return HotPotato and Receipt to Lender
        let hot = HotPotato { };
        (receipt, hot)
    }

    // repay loan
    public fun repay(lender: &signer, receipt: Receipt, hot: HotPotato) acquires FACoinPoolController {
        // Retrieve amount and metadata from receipts
        let Receipt{amount, metadata} = receipt;

        // Transfer coins from the lender to the FACoinItem
        let faCionItem_addr = get_FACoinItem_object_address(object::object_address<Metadata>(&metadata));
        primary_fungible_store::transfer(lender, metadata, faCionItem_addr, amount);

        // Deconstructing HotPotato
        let HotPotato{ } = hot;
    }

    // ======================== Read Functions ========================
    #[view]
    fun get_UserStake(faCoin_addr: address): SimpleMap<address, u64> acquires UserStake {
        let user_stake_table = borrow_global<UserStake>(@FlashLoan);
        *table::borrow(&user_stake_table.stake_table, faCoin_addr)
    }

    // ================================= help() ================================= //
    /// get FACoin fungible_asset::Metadata
    fun get_Metadata(faCoin_addr: address): Object<Metadata> {
        object::address_to_object<Metadata>(faCoin_addr)
    }
    
    /// Construct FACoinItem object seed
    fun construct_FACoinItem_seed(faCoin_addr: address): vector<u8> {
        bcs::to_bytes(&string_utils::format2(&b"{}_staker_{}", @FlashLoan, faCoin_addr))
    }
    
    /// Generate signer to generate FACoinUser Object
    fun generate_FACoinPool_signer(): signer acquires FACoinPoolController {
        object::generate_signer_for_extending(&borrow_global<FACoinPoolController>(@FlashLoan).extend_ref)
    }

    // return FACoinItem Object address
    #[view]
    fun get_FACoinItem_object_address(faCoin_addr: address): address acquires FACoinPoolController {
        object::create_object_address(
            &signer::address_of(&generate_FACoinPool_signer()),
            construct_FACoinItem_seed(faCoin_addr)
        )
    }

    // get FACoinItem Object signer
    fun get_FACoinItem_object_signer(faCoin_addr: address): signer acquires FACoinItemController, FACoinPoolController {
        let faCoinPool_addr = signer::address_of(&generate_FACoinPool_signer());
        let faCoinItem_extendref_table = &borrow_global<FACoinItemController>(faCoinPool_addr).ControllerList;
        let extend_ref = table::borrow(faCoinItem_extendref_table, faCoin_addr);
        object::generate_signer_for_extending(extend_ref)
    }

    /// get user stake amount for a FACoin
    fun get_user_stake_amount(faCoin_addr: address, user_addr: address): u64 acquires UserStake {
        let user_stake_table = borrow_global_mut<UserStake>(@FlashLoan);
        let faCoin_stake_map = table::borrow_mut(&mut user_stake_table.stake_table, faCoin_addr);
        if(simple_map::contains_key(faCoin_stake_map, &user_addr)) {
            *simple_map::borrow(faCoin_stake_map, &user_addr)
        } else {
            simple_map::add(faCoin_stake_map, user_addr, 0);
            0
        }
    }

    /// update user stake amount for a FACoin
    fun update_user_stake_amount(faCoin_addr: address, user_addr: address, amount: u64) acquires UserStake {
        let user_stake_table = borrow_global_mut<UserStake>(@FlashLoan);
        let faCoin_stake_map = table::borrow_mut(&mut user_stake_table.stake_table, faCoin_addr);
        simple_map::upsert(faCoin_stake_map, user_addr, amount);
    }

    /// transfer FACoin
    fun transfer_FACoin(faCoin_addr: address, from: &signer, to: address, amount: u64) {
        let metadata = get_Metadata(faCoin_addr);
        let fa = primary_fungible_store::withdraw(from, metadata, amount);
        primary_fungible_store::deposit(to, fa);
    }
}