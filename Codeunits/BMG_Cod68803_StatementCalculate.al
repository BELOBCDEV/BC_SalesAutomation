codeunit 68803 "BMG LSC Statement-Calculate"
{
    Permissions = TableData "LSC Tender Type" = r,
                  TableData "LSC Trans. Tender Declar. Entr" = rm,
                  TableData "LSC Transaction Header" = rm,
                  TableData "LSC Trans. Sales Entry" = rm,
                  TableData "LSC Trans. Payment Entry" = rm,
                  TableData "LSC Trans. Inc./Exp. Entry" = rm,
                  TableData "LSC Trans. Infocode Entry" = rm,
                  TableData "LSC Statement" = rmd,
                  TableData "LSC Statement Line" = rimd,
                  TableData "LSC Tender TP Card No. Series" = r;
    TableNo = "LSC Statement";

    trigger OnRun()
    var
        StartCalc: Label 'Start of statement calculation';
        EndCalc: Label 'Calculation finished without errors';
        WarningCounter: Label '%1 warnings or errors were generated while calculating the statement';
        IsHandled: Boolean;
    begin
        LockTimeOut(false);

        OnBeforeRunCodeunit(Rec);
        CurrentStatementRecord := Rec;

        DeleteWarningComments(Rec."No.");
        InsertComment(Rec."No.", StartCalc, false);
        CommentLineCounter -= 1;
        InitTmpTables();

        StatementLine2.Reset();
        StatementLine2.SetRange("Statement No.", Rec."No.");
        StatementLine2.SetRange("Store No.", Rec."Store No.");
        if StatementLine2.FindLast() then
            NextLine := StatementLine2."Line No." + 10000
        else
            NextLine := 10000;

        SafeStatementLine2.Reset();
        SafeStatementLine2.SetRange("Statement No.", Rec."No.");
        SafeStatementLine2.SetRange("Store No.", Rec."Store No.");
        if SafeStatementLine2.FindLast() then
            NextSafeLine := SafeStatementLine2."Line No." + 10000
        else
            NextSafeLine := 10000;

        StatementLine2.Reset();
        StatementLine2.SetCurrentKey("Statement No.", "Statement Code", "Staff ID",
          "POS Terminal No.", "Tender Type", "Tender Type Card No.", "Currency Code");
        StatementLine2.SetRange("Statement No.", Rec."No.");
        StatementLine2.SetRange("Store No.", Rec."Store No.");

        SafeStatementLine2.Reset();
        SafeStatementLine2.SetCurrentKey("Statement No.", "Statement Code", "Staff ID",
          "POS Terminal No.", "Tender Type", "Currency Code", "Bal. Account No.", "Bag No.");
        SafeStatementLine2.SetRange("Statement No.", Rec."No.");
        SafeStatementLine2.SetRange("Store No.", Rec."Store No.");

        Clear(TmpEndOfDayEntry);
        TmpEndOfDayEntry.DeleteAll();

        Clear(TmpEndOfDayComment);
        TmpEndOfDayComment.DeleteAll();

        Store.Get(Rec."Store No.");
        if not FuncProfile.Get(Store."Functionality Profile") then
            if not FuncProfile.Get(Format("LSC POS Profile ID"::DefaultFunctionality)) then
                Clear(FuncProfile);

        if Rec."Closing Method" = Rec."Closing Method"::Shift then
            CalcByShift(Rec)
        else
            CalcByDateTime(Rec);

        OnBeforeShowErrorLineCounter(ErrorLineCounter, IsHandled);
        /*
        if not IsHandled then begin
            if GuiAllowed then
                if ErrorLineCounter > 0 then
                    Message(WarningCounter, ErrorLineCounter);
        end;
        */

        Clear(TmpEndOfDayEntry);
        TmpEndOfDayEntry.DeleteAll();

        InsertComment(Rec."No.", EndCalc, false);
        OnAfterRunCodeunit(Rec);
    end;

    var
        StatementLine: Record "LSC Statement Line";
        StatementLine2: Record "LSC Statement Line";
        Transaction: Record "LSC Transaction Header";
        TransSalesEntry: Record "LSC Trans. Sales Entry";
        TransPmtEntry: Record "LSC Trans. Payment Entry";
        TransInvEntry: Record "LSC Trans. Inventory Entry";
        TransIncomeExpenseEntry: Record "LSC Trans. Inc./Exp. Entry";
        TransTenderDeclarEntry: Record "LSC Trans. Tender Declar. Entr";
        TenderType: Record "LSC Tender Type";
        TenderTypeCardSetup: Record "LSC Tender Type Card Setup";
        POSTerminal: Record "LSC POS Terminal";
        Store: Record "LSC Store";
        Item: Record Item;
        Customer: Record Customer;
        CashDeclaration: Record "LSC Cash Declaration";
        TransSafeEntry: Record "LSC Trans. Safe Entry";
        SafeStatementLine: Record "LSC Safe Statement Line";
        SafeStatementLine2: Record "LSC Safe Statement Line";
        FuncProfile: Record "LSC POS Func. Profile";
        CurrentStatementRecord: Record "LSC Statement";
        PosTerminalTemp: Record "LSC POS Terminal" temporary;
        POSTerminalTemp2: Record "LSC POS Terminal" temporary;
        TmpDeclEntry: Record "LSC Trans. Tender Declar. Entr" temporary;
        TmpEndOfDayEntry: Record "LSC POS Start Status" temporary;
        TmpEndOfDayComment: Record "LSC POS Start Status" temporary;
        TmpTrans: Record "LSC Transaction Header" temporary;
        ItemTrack: Codeunit "LSC Retail Item Tracking";
        BufferUtility: Codeunit "LSC Buffer Utility";
        LastType: Code[10];
        LastCurr: Code[10];
        LastCode: Code[20];
        LastCard: Code[10];
        WrkStaffID: Code[20];
        WrkPOSTerminalNo: Code[10];
        LastStaffID: Code[20];
        TotAmount: Decimal;
        TotCurrAmount: Decimal;
        TotRemovedAmount: Decimal;
        TotAddedAmount: Decimal;
        TotChange: Decimal;
        NextLine: Integer;
        CommentLineCounter: Integer;
        NextSafeLine: Integer;
        LastCommentNo: Integer;
        ErrorLineCounter: Integer;
        NoOfRec: Integer;
        Counter: Integer;
        Text005: Label 'Calculating Statement\\';
        Text009: Label 'Unknown Tender Type';

    local procedure IsItemSNTracking(pItemNo: Code[20]): Boolean
    var
        Item: Record Item;
        ItemTrackCode: Record "Item Tracking Code";
        ItemTracking: Boolean;
    begin
        ItemTracking := false;

        if Item.Get(pItemNo) then
            if Item."Item Tracking Code" <> '' then
                if ItemTrackCode.Get(Item."Item Tracking Code") then
                    if ItemTrackCode."SN Specific Tracking" then
                        ItemTracking := true;

        exit(ItemTracking);
    end;

    local procedure IsItemLotTracking(pItemNo: Code[20]): Boolean
    var
        Item: Record Item;
        ItemTrackCode: Record "Item Tracking Code";
        ItemTracking: Boolean;
    begin
        ItemTracking := false;

        if Item.Get(pItemNo) then
            if Item."Item Tracking Code" <> '' then
                if ItemTrackCode.Get(Item."Item Tracking Code") then
                    if ItemTrackCode."Lot Specific Tracking" then
                        ItemTracking := true;

        exit(ItemTracking);
    end;

    local procedure GetStrictExpirationPosting(pItemNo: Code[20]): Boolean
    var
        Item: Record Item;
        ItemTrackCode: Record "Item Tracking Code";
    begin
        exit(GetStrictExpirationPosting(pItemNo, Item, ItemTrackCode));
    end;

    local procedure GetStrictExpirationPosting(pItemNo: Code[20]; var Item: Record Item; var ItemTrackCode: Record "Item Tracking Code"): Boolean
    begin
        if not Item.Get(pItemNo) then
            exit(false);

        if Item."Item Tracking Code" = '' then
            exit(false);

        if not ItemTrackCode.Get(Item."Item Tracking Code") then
            exit(false);

        exit(ItemTrackCode."Strict Expiration Posting");
    end;

    local procedure CalcByDateTime(var Statement: Record "LSC Statement")
    var
        RetailCommentLine: Record "LSC Retail Comment Line";
        Window: Dialog;
        ConfirmTxt: Text[250];
        TimeTxt: Text[100];
        StaffPOSFilter: Text[100];
        SavedErrLineCounter: Integer;
        Skip: Boolean;
        AbortTxt: Label 'Aborting';
        TransWarning: Label 'The system found %1 possible error(s) when checking the %2. Do you want to continue?';
        Text004: Label 'with date between %1 and %2 %3 \with the statement number?';
        Text003: Label 'with date %1 %2 \with the statement number?';
        Text002: Label 'with date on or before %1 %2 \with the statement number?';
        Text001: Label 'Do you want to calculate the statement and mark all transactions\';
        Text000: Label 'and time between %1 and %2';
    begin
        OnBeforeCalcByDateTime(Statement);
        Statement.TestField("Trans. Ending Date");
        Statement.TestField("Trans. Starting Date");
        Statement.TestField("Store No.");

        Store.Get(Statement."Store No.");
        Statement.Method := Store."Statement Method";

        PosTerminalTemp.DeleteAll();
        POSTerminal.Reset();
        POSTerminal.SetCurrentKey("Store No.");
        POSTerminal.SetRange("Store No.", Statement."Store No.");
        if POSTerminal.FindSet() then
            repeat
                PosTerminalTemp := POSTerminal;
                if not POSTerminal."Terminal Statement" then
                    PosTerminalTemp."Statement Method" := Store."Statement Method";
                PosTerminalTemp.Insert();
            until POSTerminal.Next() = 0;

        /*
        if not Statement."Skip Confirmation" then begin
            if (Statement."Trans. Ending Time" <> 0T) or (Statement."Trans. Starting Time" <> 0T) then
                TimeTxt := StrSubstNo(Text000, Statement."Trans. Starting Time", Statement."Trans. Ending Time")
            else
                TimeTxt := '';
            if Statement."Trans. Starting Date" = 0D then
                ConfirmTxt := StrSubstNo(Text001 + Text002, Statement."Trans. Ending Date", TimeTxt)
            else
                if Statement."Trans. Starting Date" = Statement."Trans. Ending Date" then
                    ConfirmTxt := StrSubstNo(Text001 + Text003, Statement."Trans. Ending Date", TimeTxt)
                else
                    ConfirmTxt := StrSubstNo(Text001 + Text004, Statement."Trans. Starting Date", Statement."Trans. Ending Date", TimeTxt);

            if not Confirm(ConfirmTxt) then
                exit;
        end;
        */

        Transaction.SetCurrentKey("Store No.", Date);
        Transaction.SetRange("Store No.", Statement."Store No.");
        Transaction.SetRange(Date, Statement."Trans. Starting Date", Statement."Trans. Ending Date");
        CheckTransactions(Transaction, Statement);
        Transaction.Reset();

        if FuncProfile."Check for Missing Transactions" then begin
            SavedErrLineCounter := ErrorLineCounter;
            CheckMissingTransFromPOS(Statement);
            Commit();  // needed to commit the RetailCommentLines
            if GuiAllowed then begin
                RetailCommentLine.FindLast();
                if ErrorLineCounter <> SavedErrLineCounter then begin
                    RetailCommentLine.SetRange("Table No.", Database::"LSC Statement");
                    RetailCommentLine.SetRange("No.", Statement."No.");
                    RetailCommentLine.SetFilter("Line No.", '>%1', LastCommentNo);
                    Page.Run(0, RetailCommentLine);
                    if not Confirm(StrSubstNo(TransWarning, ErrorLineCounter - SavedErrLineCounter, Statement.TableCaption), true) then
                        Error(AbortTxt);
                end;
            end;
        end;

        Statement."Calculated Date" := Today;
        Statement."Calculated Time" := Time;
        Transaction.SetCurrentKey("Store No.", Date);
        Transaction.SetRange("Store No.", Statement."Store No.");
        Transaction.SetRange(Date, Statement."Trans. Starting Date", Statement."Trans. Ending Date");
        Transaction.SetFilter("Transaction Type", '<>%1', Transaction."Transaction Type"::PhysInv);
        StaffPOSFilter := Statement."Staff/POS Term Filter Internal";
        if StaffPOSFilter <> '' then begin
            if Statement.Method = Statement.Method::Staff then
                Transaction.SetFilter("Staff ID", StaffPOSFilter);
            if Statement.Method = Statement.Method::"POS Terminal" then
                Transaction.SetFilter("POS Terminal No.", StaffPOSFilter);
        end;
        Transaction.SetAutoCalcFields("Posted Statement No.");

        OpenTablesBuffers();
        NoOfRec := Transaction.Count();
        Counter := 0;
        if GuiAllowed then
            Window.Open(Text005 + '@1@@@@@@@@@@@@@@@@@@@@@@@@@');

        if Transaction.FindSet() then
            repeat
                if ProcessTrans(Statement) then begin
                    Skip := false;
                    Counter := Counter + 1;
                    if GuiAllowed then
                        Window.Update(1, Round(Counter / NoOfRec * 10000, 1));
                    if Transaction.Date = Statement."Trans. Ending Date" then begin
                        if (Statement."Trans. Ending Time" <> 0T) and
                              (Statement."Trans. Ending Time" < Transaction.Time)
                        then
                            Skip := true;
                        if (Statement."Trans. Starting Time" <> 0T) and
                              (Statement."Trans. Starting Date" = 0D) and
                              (Statement."Trans. Starting Time" > Transaction.Time)
                        then
                            Skip := true;
                    end;
                    if (Transaction.Date = Statement."Trans. Starting Date") and
                       (Statement."Trans. Starting Time" <> 0T) and
                       (Statement."Trans. Starting Time" > Transaction.Time)
                    then
                        Skip := true;
                    if not Skip then
                        MarkTransaction(Statement."No.", Statement."Closing Method", Statement);
                end;
            until Transaction.Next() = 0;
        if GuiAllowed then
            Window.Close();

        InsertTendDeclLines(Statement);
        FlushTablesBuffers();
        Statement.Modify();

        StatementCheckSerialNo(Statement);
        Statement.CalcFields("No. of Blank UOM Item");
        OnAfterCalcByDateTime(Statement);
    end;

    local procedure CalcByShift(Statement: Record "LSC Statement")
    var
        Window: Dialog;
        Text006: Label 'Calculate statement and mark transactions ?';
    begin
        OnBeforeCalcByShift(Statement);
        Statement.TestField("Shift Date");
        Statement.TestField("Shift No.");
        Statement.TestField("Store No.");
        if not Statement."Skip Confirmation" then
            if not Confirm(Text006) then
                exit;

        PosTerminalTemp.DeleteAll();
        POSTerminal.Reset();
        POSTerminal.SetCurrentKey("Store No.");
        POSTerminal.SetRange("Store No.", Statement."Store No.");
        if POSTerminal.FindSet() then
            repeat
                PosTerminalTemp := POSTerminal;
                PosTerminalTemp.Insert();
            until POSTerminal.Next() = 0;

        Statement."Calculated Date" := Today;
        Statement."Calculated Time" := Time;

        Transaction.Reset();
        Transaction.SetCurrentKey("Store No.", "Shift Date", "Shift No.");
        Transaction.SetRange("Store No.", Statement."Store No.");
        Transaction.SetRange("Shift Date", Statement."Shift Date");
        Transaction.SetRange("Shift No.", Statement."Shift No.");
        CheckTransactions(Transaction, Statement);

        Transaction.Reset();
        Transaction.SetCurrentKey("Store No.", "Shift Date", "Shift No.");
        Transaction.SetRange("Store No.", Statement."Store No.");
        Transaction.SetRange("Shift Date", Statement."Shift Date");
        Transaction.SetRange("Shift No.", Statement."Shift No.");
        Transaction.SetAutoCalcFields("Posted Statement No.");

        OpenTablesBuffers();
        NoOfRec := Transaction.Count();
        Counter := 0;
        if GuiAllowed then
            Window.Open(Text005 + '@1@@@@@@@@@@@@@@@@@@@@@@@@@');

        Store.Get(Statement."Store No.");

        if Transaction.FindSet() then
            repeat
                Counter := Counter + 1;
                if GuiAllowed then
                    Window.Update(1, Round(Counter / NoOfRec * 10000, 1));
                if ProcessTrans(Statement) then
                    MarkTransaction(Statement."No.", Statement."Closing Method", Statement);
            until Transaction.Next() = 0;
        if GuiAllowed then
            Window.Close();
        InsertTendDeclLines(Statement);
        FlushTablesBuffers();
        Statement.Modify();

        StatementCheckSerialNo(Statement);
        Statement.CalcFields("No. of Blank UOM Item");
        OnAfterCalcByShift(Statement);
    end;

    local procedure MarkTransaction(StatementNo: Code[20]; StatementClosingMethod: Option "Date and Time",Shift; Stmt: Record "LSC Statement")
    var
        TransactionStatus: Record "LSC Transaction Status";
        TransSalesEntryStatus: Record "LSC Trans. Sales Entry Status";
        TransSalesEntryStatus2: Record "LSC Trans. Sales Entry Status";
        lTenderTypeRec: Record "LSC Tender Type";
        TransDiscEntry: Record "LSC Trans. Discount Entry";
        CurrExchRate: Record "Currency Exchange Rate";
        POSTerminal_l: Record "LSC POS Terminal";
        ItemStatusLink: Record "LSC Item Status Link";
        recBMGCustomer: Record BMGCustomers;
        BOUtils: Codeunit "LSC BO Utils";
        ErrorText: Text[250];
        StoreCurrFactor: Decimal;
        UpdateTransSalesEntry, NewTransSalesEntryStatus, SerLotNoNotFound, ItemPosted, IsHandled : Boolean;
    begin
        OnBeforeMarkTransaction(Transaction, CurrentStatementRecord);
        TransSalesEntry.Reset();
        TransPmtEntry.Reset();
        TransTenderDeclarEntry.Reset();

        TransSafeEntry.Reset();

        GetTransStatusFromBuffer(Transaction, TransactionStatus);
        OnAfterGetTransStatusFromBuffer(StatementNo, Transaction, TransactionStatus);

        TransactionStatus."Statement No." := StatementNo;
        TransactionStatus."Items Blocked" := 0;

        if Transaction."Wrong Shift" then
            TransactionStatus."Trans. on Wrong Shift" := 1
        else
            TransactionStatus."Trans. on Wrong Shift" := 0;

        TransactionStatus."Items/Barc. Not on File" := 0;
        TransactionStatus."Sales Amount" := 0;
        TransactionStatus."VAT Amount" := 0;
        TransactionStatus."Total Discount" := 0;
        TransactionStatus."Line Discount" := 0;
        TransactionStatus."Discount Total Amount" := 0;
        TransactionStatus.Income := 0;
        TransactionStatus.Expenses := 0;
        TransactionStatus."No of Trans. Sales Entries" := 0;
        TransactionStatus."Serial/Lot No. Not Valid" := 0;
        TransactionStatus."No. of Blank UOM Item" := 0;

        if Transaction."Customer No." <> '' then begin
            if Customer.Get(Transaction."Customer No.") then
                if Customer.Blocked <> Customer.Blocked::" " then
                    TransactionStatus."Blocked Customer" := true;

            //insert Customer if not found-----
            if not Customer.Get(Transaction."Customer No.") then begin
                recBMGCustomer.Reset();
                recBMGCustomer.SetRange("No.", Transaction."Customer No.");

                if recBMGCustomer.FindFirst() then begin
                    Customer.Init();
                    Customer.TransferFields(recBMGCustomer);
                    if Customer.Insert() then;
                end;
            end

        end;

        if Transaction."Transaction Code" = Transaction."Transaction Code"::"Sale/Pmt. Difference" then
            TransactionStatus."Sale/Pmt. Difference" := true;

        TransSalesEntry.SetRange("Store No.", Transaction."Store No.");
        TransSalesEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
        TransSalesEntry.SetRange("Transaction No.", Transaction."Transaction No.");

        TransPmtEntry.SetRange("Store No.", Transaction."Store No.");
        TransPmtEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
        TransPmtEntry.SetRange("Transaction No.", Transaction."Transaction No.");

        TransIncomeExpenseEntry.SetRange("Store No.", Transaction."Store No.");
        TransIncomeExpenseEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
        TransIncomeExpenseEntry.SetRange("Transaction No.", Transaction."Transaction No.");

        TransTenderDeclarEntry.SetRange("Store No.", Transaction."Store No.");
        TransTenderDeclarEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
        TransTenderDeclarEntry.SetRange("Transaction No.", Transaction."Transaction No.");

        TransSafeEntry.SetRange("Store No.", Transaction."Store No.");
        TransSafeEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
        TransSafeEntry.SetRange("Transaction No.", Transaction."Transaction No.");

        TransDiscEntry.SetRange("Store No.", Transaction."Store No.");
        TransDiscEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
        TransDiscEntry.SetRange("Transaction No.", Transaction."Transaction No.");

        TransInvEntry.Reset();
        TransInvEntry.SetRange("Store No.", Transaction."Store No.");
        TransInvEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
        TransInvEntry.SetRange("Transaction No.", Transaction."Transaction No.");
        TransInvEntry.ModifyAll("Statement No.", StatementNo);

        if TransSalesEntry.FindSet() then
            repeat
                TransactionStatus."No of Trans. Sales Entries" := TransactionStatus."No of Trans. Sales Entries" + 1;
                UpdateTransSalesEntry := false;
                if Item.Get(TransSalesEntry."Item No.") then begin
                    BOUtils.IsBlockSaleInSO(Item."No.", '', TransSalesEntry."Variant Code", Store."No.", Store."Location Code", Today, ItemStatusLink);
                    if (Item.Blocked) or (ItemStatusLink."Block Sale in Sales Order") then begin
                        TransactionStatus."Items Blocked" := TransactionStatus."Items Blocked" + 1;
                        TransSalesEntry."Transaction Code" := TransSalesEntry."Transaction Code"::"Item Blocked";
                        UpdateTransSalesEntry := true;
                    end;
                end
                else begin
                    TransactionStatus."Items/Barc. Not on File" := TransactionStatus."Items/Barc. Not on File" + 1;
                    TransSalesEntry."Transaction Code" := TransSalesEntry."Transaction Code"::"Item/Barcode Not On File";
                    UpdateTransSalesEntry := true;
                end;

                ItemPosted := false;
                if TransSalesEntryStatus2.Get(TransSalesEntry."Store No.",
                      TransSalesEntry."POS Terminal No.",
                      TransSalesEntry."Transaction No.",
                      TransSalesEntry."Line No.")
                then
                    if TransSalesEntryStatus2.Status in [TransSalesEntryStatus2.Status::"Items Posted", TransSalesEntryStatus2.Status::Posted] then
                        ItemPosted := true;

                if (TransSalesEntry."Serial No." <> '') and (not ItemPosted) then begin
                    SerLotNoNotFound := TransSalesEntry."Serial/Lot No. Not Valid";
                    TransSalesEntry."Serial/Lot No. Not Valid" := not TransSalesCheckSerialNo(TransSalesEntry, ErrorText);
                    if TransSalesEntry."Serial/Lot No. Not Valid" <> SerLotNoNotFound then
                        UpdateTransSalesEntry := true;
                end;
                if (TransSalesEntry."Lot No." <> '') and (not ItemPosted) then
                    if not ((TransSalesEntry."Serial No." <> '') and (TransSalesEntry."Serial/Lot No. Not Valid")) then begin
                        OnCheckLotNo(TransSalesEntry, IsHandled);
                        if not IsHandled then begin
                            SerLotNoNotFound := TransSalesEntry."Serial/Lot No. Not Valid";
                            TransSalesEntry."Serial/Lot No. Not Valid" := not TransSalesCheckLotNo(StatementNo, TransSalesEntry, ErrorText);
                            if TransSalesEntry."Serial/Lot No. Not Valid" <> SerLotNoNotFound then
                                UpdateTransSalesEntry := true;
                        end;
                    end;

                if TransSalesEntry."Serial/Lot No. Not Valid" then
                    TransactionStatus."Serial/Lot No. Not Valid" := TransactionStatus."Serial/Lot No. Not Valid" + 1;

                if TransSalesEntry."Blank UOM Item" then
                    TransactionStatus."No. of Blank UOM Item" := TransactionStatus."No. of Blank UOM Item" + 1;
                OnBeforeUpdateTransSalesEntryOfMarkTransaction(TransSalesEntry, UpdateTransSalesEntry, StatementNo);
                if UpdateTransSalesEntry then
                    TransSalesEntryToBuffer(TransSalesEntry);

                TransactionStatus."Sales Amount" := TransactionStatus."Sales Amount" + TransSalesEntry."Net Amount";
                TransactionStatus."VAT Amount" := TransactionStatus."VAT Amount" + TransSalesEntry."VAT Amount";
                TransactionStatus."Total Discount" := TransactionStatus."Total Discount" + TransSalesEntry."Total Discount";
                if TransSalesEntry."Line was Discounted" then
                    TransactionStatus."Line Discount" := TransactionStatus."Line Discount" + TransSalesEntry."Line Discount";
                if not TransSalesEntryStatus.Get(TransSalesEntry."Store No.",
                      TransSalesEntry."POS Terminal No.",
                      TransSalesEntry."Transaction No.",
                      TransSalesEntry."Line No.")
                then begin
                    NewTransSalesEntryStatus := true;
                    TransSalesEntryStatus.Init();
                    TransSalesEntryStatus."Store No." := TransSalesEntry."Store No.";
                    TransSalesEntryStatus."POS Terminal No." := TransSalesEntry."POS Terminal No.";
                    TransSalesEntryStatus."Transaction No." := TransSalesEntry."Transaction No.";
                    TransSalesEntryStatus."Line No." := TransSalesEntry."Line No.";
                end else
                    NewTransSalesEntryStatus := false;
                TransSalesEntryStatus."Statement No." := StatementNo;
                TransSalesEntryStatus."Item No." := TransSalesEntry."Item No.";
                TransSalesEntryStatus."Variant Code" := TransSalesEntry."Variant Code";
                TransSalesEntryStatus.Quantity := TransSalesEntry.Quantity;
                TransSalesEntryStatus.Date := TransSalesEntry.Date;
                TransSalesEntryStatus."Serial No." := TransSalesEntry."Serial No.";
                TransSalesEntryStatus."Lot No." := TransSalesEntry."Lot No.";

                OnMarkTransOnBeforeTransSalesEntryStatusToBuffer(TransSalesEntryStatus);
                TransSalesEntryStatusToBuffer(TransSalesEntryStatus);
            until TransSalesEntry.Next() = 0;

        if TransPmtEntry.FindSet() then
            repeat
                if (Transaction."POS Terminal No." <> PosTerminalTemp."No.") or
                   (Transaction."Staff ID" <> LastStaffID) or
                   (LastCode = '')
                then begin
                    PopulateStatementCode(Transaction."POS Terminal No.", Transaction."Staff ID", LastCode, WrkStaffID, WrkPOSTerminalNo);
                    LastStaffID := Transaction."Staff ID";
                end;
                LastType := TransPmtEntry."Tender Type";
                LastCard := TransPmtEntry."Card No.";
                LastCurr := TransPmtEntry."Currency Code";
                if Transaction."Trans. Currency" <> '' then
                    StoreCurrFactor := CurrExchRate.ExchangeRate(Transaction.Date, Transaction."Trans. Currency")
                else
                    StoreCurrFactor := 1;

                if Store."Safe Mgnt. in Use" and
                   (Transaction."Transaction Type" in
                   [Transaction."Transaction Type"::"Remove Tender",
                   Transaction."Transaction Type"::"Float Entry",
                   Transaction."Transaction Type"::"Change Tender",
                   Transaction."Transaction Type"::"Tender Decl."])
                then begin
                    TotAmount := 0;
                    TotCurrAmount := 0;
                end
                else begin
                    TotAmount := TransPmtEntry."Amount Tendered" / StoreCurrFactor;
                    TotCurrAmount := TransPmtEntry."Amount in Currency";
                end;
                TotRemovedAmount := 0;
                TotAddedAmount := 0;
                TotChange := 0;
                case Transaction."Transaction Type" of
                    Transaction."Transaction Type"::"Remove Tender":
                        TotRemovedAmount := TotRemovedAmount + TransPmtEntry."Amount in Currency";
                    Transaction."Transaction Type"::"Float Entry":
                        TotAddedAmount := TotAddedAmount + TransPmtEntry."Amount in Currency";
                    Transaction."Transaction Type"::"Change Tender":
                        TotChange := TotChange + TransPmtEntry."Amount in Currency";
                    Transaction."Transaction Type"::"Tender Decl.":
                        TotRemovedAmount := TotRemovedAmount + TransPmtEntry."Amount in Currency";
                end;
                OnBeforeCalculateStatementLine2TransAmount(TransPmtEntry, StatementLine2, LastCurr);
                StatementLine2.SetFilter("Statement Code", '%1', LastCode);
                StatementLine2.SetFilter("Staff ID", '%1', WrkStaffID);
                StatementLine2.SetFilter("POS Terminal No.", '%1', WrkPOSTerminalNo);
                StatementLine2.SetFilter("Tender Type", '%1', LastType);
                StatementLine2.SetFilter("Tender Type Card No.", '%1', LastCard);
                StatementLine2.SetFilter("Currency Code", '%1', LastCurr);
                if StatementLine2.FindFirst() then begin
                    StatementLine2.Validate("Trans. Amount", StatementLine2."Trans. Amount" + TotCurrAmount);
                    StatementLine2.Validate("Trans. Amount in LCY", StatementLine2."Trans. Amount in LCY" + TotAmount);
                    if StatementLine2."Trans. Amount" <> 0 then
                        StatementLine2."Real Exchange Rate" := StatementLine2."Trans. Amount in LCY" / StatementLine2."Trans. Amount"
                    else begin
                        if TotCurrAmount = 0 then
                            StatementLine2."Real Exchange Rate" := 1
                        else
                            if SafeStatementLine2."Real Exchange Rate" <> 0 then
                                SafeStatementLine2."Real Exchange Rate" := (SafeStatementLine2."Real Exchange Rate" + (TotAmount / TotCurrAmount)) / 2
                            else
                                SafeStatementLine2."Real Exchange Rate" := TotAmount / TotCurrAmount;
                    end;
                    OnAfterCalcStatementLine2TransAmout(TransPmtEntry, StatementLine2);
                    if not StatementLine2."Counting Required" then begin
                        POSTerminal_l.Get(TransPmtEntry."POS Terminal No.");
                        lTenderTypeRec.Get(Transaction."Store No.", LastType);
                        StatementLine2."Counting Required" := lTenderTypeRec."Counting Required" and ((not Store."Safe Mgnt. in Use") or POSTerminal_l."Exclude from Cash Mgnt.");
                    end;
                    if StatementLine2."Counting Required" then
                        StatementLine2.Validate("Counted Amount", 0)
                    else begin
                        lTenderTypeRec.Get(Transaction."Store No.", LastType);
                        if Store."Safe Mgnt. in Use" and
                           (lTenderTypeRec."Function" <> lTenderTypeRec."Function"::"Tender Remove/Float") and
                           (lTenderTypeRec."Counting Required")
                        then
                            StatementLine2.Validate("Counted Amount", StatementLine2."Counted Amount" - TotAddedAmount - TotRemovedAmount)
                        else
                            StatementLine2.Validate("Counted Amount", StatementLine2."Trans. Amount");
                    end;
                    StatementLine2."Added to Drawer" += TotAddedAmount;
                    StatementLine2."Removed from Drawer" += TotRemovedAmount;
                    StatementLine2."Change Tender" += TotChange;
                    StatementLine2.Modify();
                end
                else begin
                    InsertLine(Stmt, PosTerminalTemp."Statement Method");
                    NextLine := NextLine + 10000;
                end;

            until TransPmtEntry.Next() = 0;

        if TransSafeEntry.FindSet() then
            repeat
                if (Transaction."POS Terminal No." <> PosTerminalTemp."No.") or
                   (Transaction."Staff ID" <> LastStaffID) or
                   (LastCode = '')
                then begin
                    PopulateStatementCode(Transaction."POS Terminal No.", Transaction."Staff ID", LastCode, WrkStaffID, WrkPOSTerminalNo);
                    LastStaffID := Transaction."Staff ID";
                end;

                InsertBankLine(Stmt, TransSafeEntry, PosTerminalTemp."Statement Method");
                NextSafeLine := NextSafeLine + 10000;
            until TransSafeEntry.Next() = 0;

        if TransIncomeExpenseEntry.FindSet() then
            repeat
                case TransIncomeExpenseEntry."Account Type" of
                    TransIncomeExpenseEntry."Account Type"::Income:
                        begin
                            TransactionStatus.Income := TransactionStatus.Income + TransIncomeExpenseEntry."Net Amount";
                            TransactionStatus."VAT Amount" := TransactionStatus."VAT Amount" + TransIncomeExpenseEntry."VAT Amount";
                        end;
                    TransIncomeExpenseEntry."Account Type"::Expense:
                        begin
                            TransactionStatus.Expenses := TransactionStatus.Expenses + TransIncomeExpenseEntry."Net Amount";
                            TransactionStatus."VAT Amount" := TransactionStatus."VAT Amount" + TransIncomeExpenseEntry."VAT Amount";
                        end;
                end;
                OnAfterCalculateIncExpAmounts(TransIncomeExpenseEntry);
            until TransIncomeExpenseEntry.Next() = 0;

        CalcAmountToBeRefunded(TransIncomeExpenseEntry, TransactionStatus);

        TmpDeclEntry.Reset();
        if not Store."Safe Mgnt. in Use" then
            if TransTenderDeclarEntry.FindSet() then
                repeat
                    if StatementClosingMethod = StatementClosingMethod::Shift then begin
                        TmpDeclEntry.SetRange("Shift Date", TransTenderDeclarEntry."Shift Date");
                        TmpDeclEntry.SetRange("Shift No.", TransTenderDeclarEntry."Shift No.");
                    end;

                    if Store."Statement Method" = Store."Statement Method"::Staff then
                        TmpDeclEntry.SetRange("Staff ID", TransTenderDeclarEntry."Staff ID");
                    if Store."Statement Method" = Store."Statement Method"::"POS Terminal" then
                        TmpDeclEntry.SetRange("POS Terminal No.", TransTenderDeclarEntry."POS Terminal No.");

                    TmpDeclEntry.SetRange("Statement Code", TransTenderDeclarEntry."Statement Code");
                    if TmpDeclEntry.FindFirst() and (TmpDeclEntry."Transaction No." <> TransTenderDeclarEntry."Transaction No.") and
                       (Store."Tend. Decl. Calculation" = Store."Tend. Decl. Calculation"::Last)
                    then
                        TmpDeclEntry.DeleteAll();
                    TmpDeclEntry.SetRange("Tender Type", TransTenderDeclarEntry."Tender Type");
                    TmpDeclEntry.SetRange("Card No.", TransTenderDeclarEntry."Card No.");
                    TmpDeclEntry.SetRange("Currency Code", TransTenderDeclarEntry."Currency Code");
                    if TmpDeclEntry.FindFirst() then begin
                        if Store."Tend. Decl. Calculation" = Store."Tend. Decl. Calculation"::Last then begin
                            TmpDeclEntry."Amount Tendered" := TransTenderDeclarEntry."Amount Tendered";
                            TmpDeclEntry."Amount in Currency" := TransTenderDeclarEntry."Amount in Currency";
                        end
                        else begin
                            TmpDeclEntry."Amount Tendered" := TmpDeclEntry."Amount Tendered" + TransTenderDeclarEntry."Amount Tendered";
                            TmpDeclEntry."Amount in Currency" := TmpDeclEntry."Amount in Currency" + TransTenderDeclarEntry."Amount in Currency";
                        end;
                        TmpDeclEntry.Modify();
                    end
                    else begin
                        TmpDeclEntry := TransTenderDeclarEntry;
                        TmpDeclEntry.Insert();
                    end;
                    OnAfterModifyInsertTmpDeclEntry(CurrentStatementRecord, Store, TmpDeclEntry, TransTenderDeclarEntry);
                until TransTenderDeclarEntry.Next() = 0;
        OnBeforeTransStatusToBufferOfMarkTransaction(TransTenderDeclarEntry, StatementNo);
        if TransDiscEntry.FindFirst() then begin
            TransDiscEntry.CalcSums("Discount Amount");
            TransactionStatus."Discount Total Amount" := TransDiscEntry."Discount Amount";
        end;

        TransStatusToBuffer(TransactionStatus);
        OnAfterMarkTransaction(Transaction, CurrentStatementRecord);
    end;

    internal procedure CalcAmountToBeRefunded(TransIncomeExpenseEntry: Record "LSC Trans. Inc./Exp. Entry"; var TransactionStatus: Record "LSC Transaction Status")
    var
        TransactionHeader: Record "LSC Transaction Header";
        IsHandled: Boolean;
    begin
        OnBeforeCalcAmountToBeRefunded(TransIncomeExpenseEntry, TransactionStatus, IsHandled);
        if IsHandled then
            exit;

        TransIncomeExpenseEntry.SetRange("Account Type", TransIncomeExpenseEntry."Account Type"::Income);
        if not TransIncomeExpenseEntry.IsEmpty() then begin
            TransactionHeader.Get(TransactionStatus."Store No.", TransactionStatus."POS Terminal No.", TransactionStatus."Transaction No.");
            if ((TransactionStatus.Income <> 0) and (TransactionStatus."Sales Amount" <> 0) and (TransactionHeader.Payment <= 0)) or
                ((TransactionStatus.Income <> 0) and (TransactionStatus."Sales Amount" = 0) and (TransactionHeader.Payment <= 0))
            then begin
                TransactionStatus."Amount to be Refunded" := TransactionStatus."Amount to be Refunded" + TransactionStatus.Income + TransactionStatus."Sales Amount" + TransactionStatus."VAT Amount" + TransactionHeader.Payment - TransactionHeader.Rounded;
                TransactionStatus."Customer Order ID" := TransactionHeader."Customer Order ID";
            end;
        end;
    end;

    local procedure InsertTendDeclLines(Statement: Record "LSC Statement")
    var
        StatementLineLocal: Record "LSC Statement Line";
        Window: Dialog;
        Text008: Label 'Processing Tender Declarations.\\';
    begin
        if GuiAllowed then
            Window.Open(Text008 + '@1@@@@@@@@@@@@@@@@@@@@@@@@@@@@@');

        TmpDeclEntry.Reset();
        StatementLineLocal.Reset();
        StatementLineLocal.SetRange("Statement No.", Statement."No.");
        Clear(PosTerminalTemp);

        TotAmount := 0;
        TotCurrAmount := 0;
        TotRemovedAmount := 0;
        TotAddedAmount := 0;
        TotChange := 0;
        Counter := 0;
        LastType := '';
        LastCurr := '';
        LastCode := '';
        LastCard := '';
        NextLine := NextLine + 10000;

        NoOfRec := TmpDeclEntry.Count();
        if TmpDeclEntry.FindSet() then
            repeat
                Counter := Counter + 1;
                if GuiAllowed then
                    Window.Update(1, Round(Counter / NoOfRec * 10000, 1));
                if (TmpDeclEntry."POS Terminal No." <> PosTerminalTemp."No.") or
                   (TmpDeclEntry."Staff ID" <> LastStaffID)
                then begin
                    PopulateStatementCode(TmpDeclEntry."POS Terminal No.", TmpDeclEntry."Staff ID", LastCode, WrkStaffID, WrkPOSTerminalNo);
                    LastStaffID := TmpDeclEntry."Staff ID";
                end;
                LastType := TmpDeclEntry."Tender Type";
                LastCard := TmpDeclEntry."Card No.";
                LastCurr := TmpDeclEntry."Currency Code";

                StatementLineLocal.SetFilter("POS Terminal No.", '%1', WrkPOSTerminalNo);
                StatementLineLocal.SetFilter("Staff ID", '%1', WrkStaffID);
                StatementLineLocal.SetFilter("Statement Code", '%1', LastCode);
                StatementLineLocal.SetRange("Tender Type", LastType);
                StatementLineLocal.SetFilter("Tender Type Card No.", '%1', LastCard);
                StatementLineLocal.SetFilter("Currency Code", '%1', LastCurr);
                TmpDeclEntry."Amount Tendered" := TmpDeclEntry."Amount Tendered" - TmpDeclEntry."Bank Amount Tendered" -
                  TmpDeclEntry."Safe Amount Tendered" - TmpDeclEntry."Fixed Float Amount Tendered";
                TmpDeclEntry."Amount in Currency" := TmpDeclEntry."Amount in Currency" - TmpDeclEntry."Bank Amount in Currency" -
                  TmpDeclEntry."Safe Amount in Currency" - TmpDeclEntry."Fixed Float Amount in Currency";
                if StatementLineLocal.FindFirst() then begin
                    if TmpDeclEntry."Amount in Currency" <> 0 then
                        StatementLineLocal.Validate("Counted Amount", StatementLineLocal."Counted Amount" + TmpDeclEntry."Amount in Currency")
                    else
                        StatementLineLocal.Validate("Counted Amount", StatementLineLocal."Counted Amount" + TmpDeclEntry."Amount Tendered");
                    OnUpdateReferenceNumber(TmpDeclEntry, StatementLineLocal);
                    StatementLineLocal.Modify();
                end
                else begin
                    TotAmount := 0;
                    TotCurrAmount := 0;
                    Transaction."POS Terminal No." := TmpDeclEntry."POS Terminal No.";
                    Transaction."Staff ID" := TmpDeclEntry."Staff ID";
                    if PosTerminalTemp."Statement Method" <> Statement.Method then begin
                        InsertLine(Statement, PosTerminalTemp."Statement Method");
                        NextLine := NextLine + 10000;
                    end else begin
                        InsertLine(Statement, Statement.Method);
                        NextLine := NextLine + 10000;
                    end;
                    if TmpDeclEntry."Amount in Currency" <> 0 then
                        StatementLine.Validate("Counted Amount", TmpDeclEntry."Amount in Currency")
                    else
                        StatementLine.Validate("Counted Amount", TmpDeclEntry."Amount Tendered");
                    OnUpdateReferenceNumber(TmpDeclEntry, StatementLine);
                    StatementLine.Modify();
                end;
            until TmpDeclEntry.Next() = 0;

        if GuiAllowed then
            Window.Close();
    end;

    local procedure InsertLine(Statement: Record "LSC Statement"; StatementMethodLoc: Option Staff,"POS Terminal",Total)
    var
        lTenderType: Record "LSC Tender Type";
        POSTerminal_l: Record "LSC POS Terminal";
        CountRequired: Boolean;
    begin
        CountRequired := true;
        case StatementMethodLoc of
            StatementMethodLoc::Staff:
                begin
                    StatementLine."Staff ID" := LastCode;
                    StatementLine."POS Terminal No." := '';
                end;
            StatementMethodLoc::"POS Terminal":
                begin
                    StatementLine."Staff ID" := '';
                    StatementLine."POS Terminal No." := LastCode;
                end;
            StatementMethodLoc::Total:
                begin
                    StatementLine."Staff ID" := '';
                    StatementLine."POS Terminal No." := '';
                end;
        end;
        StatementLine."Statement No." := Statement."No.";
        StatementLine."Line No." := NextLine;
        StatementLine."Statement Code" := LastCode;
        StatementLine."Tender Type" := LastType;
        StatementLine."Tender Type Card No." := LastCard;
        StatementLine."Currency Code" := LastCurr;
        StatementLine."Trans. Amount" := TotCurrAmount;
        StatementLine."Trans. Amount in LCY" := TotAmount;
        StatementLine."Counted Amount" := 0;
        StatementLine."Counted Amount in LCY" := 0;
        StatementLine."Store No." := Statement."Store No.";
        if TotCurrAmount <> 0 then
            StatementLine."Real Exchange Rate" := TotAmount / TotCurrAmount
        else
            StatementLine."Real Exchange Rate" := 1;
        OnBeforeValidateStatementLineTenderTypeName(Statement, LastCurr, StatementLine);
        if LastCard <> '' then begin
            if TenderTypeCardSetup.Get(
               StatementLine."Store No.", StatementLine."Tender Type", StatementLine."Tender Type Card No.")
            then begin
                StatementLine."Tender Type Name" := TenderTypeCardSetup.Description;
                CountRequired := TenderTypeCardSetup."Counting Required";
            end else
                StatementLine."Tender Type Name" := Text009;
        end else
            if TenderType.Get(StatementLine."Store No.", StatementLine."Tender Type") then begin
                StatementLine."Tender Type Name" := TenderType.Description;
                if StatementLine."POS Terminal No." <> '' then
                    POSTerminal_l.Get(StatementLine."POS Terminal No.")
                else
                    POSTerminal_l.Init();
                CountRequired := TenderType."Counting Required" and ((not Store."Safe Mgnt. in Use") or POSTerminal_l."Exclude from Cash Mgnt.");
            end else
                StatementLine."Tender Type Name" := Text009;

        StatementLine."Counting Required" := CountRequired;
        if StatementLine."Currency Code" <> '' then
            StatementLine."Tender Type Name" := StatementLine."Tender Type Name" + ' ' + StatementLine."Currency Code";

        StatementLine."Added to Drawer" := TotAddedAmount;
        StatementLine."Removed from Drawer" := TotRemovedAmount;
        StatementLine."Change Tender" := TotChange;
        if not CountRequired then begin
            lTenderType.Get(Store."No.", StatementLine."Tender Type");
            if Store."Safe Mgnt. in Use" and
               (lTenderType."Function" <> lTenderType."Function"::"Tender Remove/Float") and
               (lTenderType."Counting Required")
            then
                StatementLine.Validate("Counted Amount", -TotAddedAmount - TotRemovedAmount)
            else
                StatementLine.Validate("Counted Amount", StatementLine."Trans. Amount");
        end else
            StatementLine.Validate("Counted Amount", 0);
        if Statement."Posted Date" <> 0D then
            StatementLine."Posted Date" := Statement."Posted Date"
        else
            StatementLine."Posted Date" := Statement."Posting Date";
        OnBeforeInsertStatementLine(StatementLine, Store, POSTerminal);
        StatementLine.Insert(true);
    end;

    procedure SetTransactionsFree(Statement: Record "LSC Statement")
    var
        TransactionStatus: Record "LSC Transaction Status";
        TransSalesEntryStatus: Record "LSC Trans. Sales Entry Status";
        RetailCommentLine: Record "LSC Retail Comment Line";
        WorkShiftRBO: Record "LSC Work Shift RBO";
    begin
        TransactionStatus.Reset();
        TransactionStatus.SetCurrentKey("Statement No.");
        TransactionStatus.SetRange("Statement No.", Statement."No.");
        TransactionStatus.ModifyAll("Statement No.", '', true);

        TransSalesEntryStatus.Reset();
        TransSalesEntryStatus.SetCurrentKey("Statement No.");
        TransSalesEntryStatus.SetRange("Statement No.", Statement."No.");
        TransSalesEntryStatus.ModifyAll("Statement No.", '', true);

        CashDeclaration.Reset();
        CashDeclaration.SetRange("Statement No.", Statement."No.");
        CashDeclaration.DeleteAll(true);

        StatementLine.Reset();
        StatementLine.SetRange("Statement No.", Statement."No.");
        StatementLine.DeleteAll();

        SafeStatementLine.Reset();
        SafeStatementLine.SetRange("Statement No.", Statement."No.");
        SafeStatementLine.DeleteAll();

        RetailCommentLine.SetRange("Table No.", Database::"LSC Statement");
        RetailCommentLine.SetRange("No.", Statement."No.");
        RetailCommentLine.DeleteAll();

        WorkShiftRBO.Reset();
        WorkShiftRBO.SetCurrentKey("Statement No.");
        WorkShiftRBO.SetRange("Statement No.", Statement."No.");
        WorkShiftRBO.ModifyAll("Statement No.", '', true);

        OnAfterSetTransactionsFree(Statement);
    end;

    local procedure ProcessTrans(Statement: Record "LSC Statement"): Boolean
    var
        TransactionStatus: Record "LSC Transaction Status";
        StatementPost: Codeunit "LSC Statement-Post";
        IsHandled, ReturnValue : Boolean;
    begin
        OnBeforeProcessTransaction(Transaction, Statement, IsHandled, ReturnValue);
        if IsHandled then
            exit(ReturnValue);

        if Transaction."Entry Status" <> Transaction."Entry Status"::" " then
            exit(false);

        if Transaction."Posted Statement No." <> '' then
            exit(false);

        if not IsTransWithEndOfDay(Transaction, Statement) then
            exit(false);

        //if not StatementPost.CheckTransSubTables(Transaction) then
        //    exit(false);

        if not TransactionStatus.Get(Transaction."Store No.", Transaction."POS Terminal No.", Transaction."Transaction No.") then begin
            TransactionStatus.Init();
            TransactionStatus."Store No." := Transaction."Store No.";
            TransactionStatus."POS Terminal No." := Transaction."POS Terminal No.";
            TransactionStatus."Transaction No." := Transaction."Transaction No.";
            TransactionStatus."Customer No." := Transaction."Customer No.";
            TransactionStatus."Amount to Account" := Transaction."Amount to Account";
            TransactionStatus.Date := Transaction.Date;
            TransStatusToBuffer(TransactionStatus);
            exit(true);
        end else begin
            TransStatusToBuffer(TransactionStatus);
            exit(TransactionStatus."Statement No." = '');
        end;
        OnAfterProcessTransaction(Transaction, Statement);
    end;

    local procedure InitTmpTables()
    begin
        TmpDeclEntry.DeleteAll();
    end;

    local procedure PopulateStatementCode(POSTermNo: Code[10]; StaffID: Code[20]; var RetStatementCode: Code[20]; var RetStaffID: Code[20]; var RetPOSTerminalNo: Code[10])
    begin
        if PosTerminalTemp."No." <> POSTermNo then
            PosTerminalTemp.Get(POSTermNo);

        RetStatementCode := '';
        RetStaffID := '';
        RetPOSTerminalNo := '';

        if PosTerminalTemp."Statement Method" <> Store."Statement Method" then
            case PosTerminalTemp."Statement Method" of
                PosTerminalTemp."Statement Method"::Staff:
                    begin
                        RetStatementCode := StaffID;
                        RetStaffID := StaffID;
                    end;
                PosTerminalTemp."Statement Method"::"POS Terminal":
                    begin
                        RetStatementCode := POSTermNo;
                        RetPOSTerminalNo := POSTermNo;
                    end;
                PosTerminalTemp."Statement Method"::Total:
                    RetStatementCode := '';
            end
        else
            case Store."Statement Method" of
                Store."Statement Method"::Staff:
                    begin
                        RetStatementCode := StaffID;
                        RetStaffID := StaffID;
                    end;
                Store."Statement Method"::"POS Terminal":
                    begin
                        RetStatementCode := POSTermNo;
                        RetPOSTerminalNo := POSTermNo;
                    end;
                Store."Statement Method"::Total:
                    RetStatementCode := '';
            end;
    end;

    local procedure IsSerialNoInTransSalesEntry(pTransSalesEntry: Record "LSC Trans. Sales Entry"): Boolean
    var
        TransSalesEntry_Loc: Record "LSC Trans. Sales Entry";
        TransactionStatus: Record "LSC Transaction Status";
    begin
        TransSalesEntry_Loc.Reset();
        TransSalesEntry_Loc.SetCurrentKey("Item No.", "Variant Code");
        TransSalesEntry_Loc.SetRange("Item No.", pTransSalesEntry."Item No.");
        TransSalesEntry_Loc.SetRange("Variant Code", pTransSalesEntry."Variant Code");
        TransSalesEntry_Loc.SetRange("Serial No.", pTransSalesEntry."Serial No.");
        if pTransSalesEntry.Quantity >= 0 then
            TransSalesEntry_Loc.SetFilter(Quantity, '>=0')
        else
            TransSalesEntry_Loc.SetFilter(Quantity, '<0');
        if TransSalesEntry_Loc.FindSet() then
            repeat
                if (TransSalesEntry_Loc."Store No." <> pTransSalesEntry."Store No.") or
                   (TransSalesEntry_Loc."POS Terminal No." <> pTransSalesEntry."POS Terminal No.") or
                   (TransSalesEntry_Loc."Transaction No." <> pTransSalesEntry."Transaction No.") or
                   (TransSalesEntry_Loc."Line No." <> pTransSalesEntry."Line No.")
                then
                    if TransactionStatus.Get(TransSalesEntry_Loc."Store No.",
                       TransSalesEntry_Loc."POS Terminal No.",
                       TransSalesEntry_Loc."Transaction No.")
                    then
                        if TransactionStatus.Status = TransactionStatus.Status::" " then
                            exit(true);
            until TransSalesEntry_Loc.Next() = 0;
        exit(false);
    end;

    local procedure InsertBankLine(Statement: Record "LSC Statement"; TrSafeEntry: Record "LSC Trans. Safe Entry"; StatementMethodLoc: Option Staff,"POS Terminal",Total)
    var
        GLAcc: Record "G/L Account";
        BankAcc: Record "Bank Account";
        SafeLedgerEntry: Record "LSC Safe Ledger Entry";
    begin
        SafeStatementLine2.SetRange("Statement Code", LastCode);
        case StatementMethodLoc of
            StatementMethodLoc::Staff:
                begin
                    SafeStatementLine2.SetRange("Staff ID", LastCode);
                    SafeStatementLine2.SetRange("POS Terminal No.", '');
                end;
            StatementMethodLoc::"POS Terminal":
                begin
                    SafeStatementLine2.SetRange("Staff ID", '');
                    SafeStatementLine2.SetRange("POS Terminal No.", LastCode);
                end;
        end;
        Clear(SafeStatementLine);
        case StatementMethodLoc of
            StatementMethodLoc::Staff:
                begin
                    SafeStatementLine."Staff ID" := LastCode;
                    SafeStatementLine."POS Terminal No." := '';
                end;
            StatementMethodLoc::"POS Terminal":
                begin
                    SafeStatementLine."Staff ID" := '';
                    SafeStatementLine."POS Terminal No." := LastCode;
                end;
        end;
        SafeStatementLine."Statement No." := Statement."No.";
        SafeStatementLine."Line No." := NextSafeLine;
        SafeStatementLine."Statement Code" := LastCode;
        SafeStatementLine."Transaction Type" := TrSafeEntry."Transaction Type";
        SafeStatementLine."Tender Type" := TrSafeEntry."Tender Type";
        SafeStatementLine."Tender Type Card No." := TrSafeEntry."Card No.";
        SafeStatementLine."Currency Code" := TrSafeEntry."Currency Code";
        SafeStatementLine."Bal. Account Type" := TrSafeEntry."Bal. Account Type";
        SafeStatementLine."Bal. Account No." := TrSafeEntry."Bal. Account No.";
        if SafeStatementLine."Bal. Account Type" = SafeStatementLine."Bal. Account Type"::"G/L Account" then begin
            GLAcc.Get(SafeStatementLine."Bal. Account No.");
            SafeStatementLine."Bal. Account Name" := GLAcc.Name;
        end else
            if SafeStatementLine."Bal. Account Type" = SafeStatementLine."Bal. Account Type"::"Bank Account" then begin
                BankAcc.Get(SafeStatementLine."Bal. Account No.");
                SafeStatementLine."Bal. Account Name" := BankAcc.Name;
            end;

        SafeStatementLine."Bag No." := TrSafeEntry."Bank Bag No.";
        SafeStatementLine."Trans. Amount" := TrSafeEntry."Amount in Currency";
        SafeStatementLine."Trans. Amount in LCY" := TrSafeEntry."Amount Tendered";
        SafeStatementLine.Amount := 0;
        SafeStatementLine."Amount in LCY" := 0;
        SafeStatementLine."Store No." := Statement."Store No.";
        if TrSafeEntry."Amount in Currency" <> 0 then
            SafeStatementLine."Real Exchange Rate" := Round(TrSafeEntry."Amount Tendered" / TrSafeEntry."Amount in Currency", 0.000001)
        else
            SafeStatementLine."Real Exchange Rate" := 1;
        OnBeforeValidateSafeStatemetLineDescription(SafeStatementLine);
#pragma warning disable AL0432        
        if TrSafeEntry.Description <> '' then
            SafeStatementLine.Description := TrSafeEntry.Description
        else
            if TenderType.Get(SafeStatementLine."Store No.", SafeStatementLine."Tender Type") then
                SafeStatementLine.Description := TenderType.Description
            else
                SafeStatementLine.Description := Text009;

        if (SafeStatementLine."Currency Code" <> '') and (StrPos(SafeStatementLine.Description, SafeStatementLine."Currency Code") = 0) then
            SafeStatementLine.Description :=
              CopyStr(StrSubstNo('%1 %2', SafeStatementLine.Description, SafeStatementLine."Currency Code"), 1, MaxStrLen(SafeStatementLine.Description));
#pragma warning restore AL0432
        SafeStatementLine.Validate(Amount, SafeStatementLine."Trans. Amount");
        SafeStatementLine."Safe No." := TrSafeEntry."Safe No.";
        SafeLedgerEntry.SetCurrentKey("Store No.", "POS Terminal No.", "Transaction No.");
        SafeLedgerEntry.SetRange("Store No.", TrSafeEntry."Store No.");
        SafeLedgerEntry.SetRange("POS Terminal No.", TrSafeEntry."POS Terminal No.");
        SafeLedgerEntry.SetRange("Transaction No.", TrSafeEntry."Transaction No.");
        SafeLedgerEntry.SetRange("Line No.", TrSafeEntry."Line No.");
        if SafeLedgerEntry.FindFirst() then
            SafeStatementLine."Safe Ledger Entry No." := SafeLedgerEntry."Entry No.";
        SafeStatementLine.Insert();
        OnBeforeInsertSafeStatemetLine(Statement, SafeStatementLine, TrSafeEntry);
    end;

    local procedure CheckTransactions(var Transaction: Record "LSC Transaction Header"; var Statement: Record "LSC Statement")
    var
        POSTerminal_Loc: Record "LSC POS Terminal";
        FirstTransaction: Record "LSC Transaction Header";
        LastTransaction: Record "LSC Transaction Header";
        SalesEntry: Record "LSC Trans. Sales Entry";
        PaymentEntry: Record "LSC Trans. Payment Entry";
        TransactionHeaderCount: Record "LSC Transaction Header";
        TmpPOS: Record "LSC POS Terminal" temporary;
        ItemCount: Decimal;
        TransCount: Integer;
        PaymentEntryCount: Integer;
        TransTrainCount: Integer;
        TransactionIsOutsideTimeRange: Boolean;
        IsHandled: Boolean;
        LastTransNotLogoff: Label 'Warning - The last %1 from %2 %3 is not a Logoff transaction';
        PrevTransMissing: Label 'Warning - %1 %2 from %3 %4, %5 %6 seems to be missing';
        SalesEntryMissing: Label 'Warning - Calculated item quantity %1 from %3 %4 does not match the registered quantity %2';
        EntryMissing: Label 'Warning - %1 %2 records were found from %3 %4, %5 were expected';
    begin
        // The purpose of this function is to check if all the transactions within the statement
        // are in sequence. This helps spot missing transactions that might have been lost due to
        // database corruption or similar incidents.

        // We start by buffering up the POS Terminals that are present in the statement. This would
        // not be necessary if we had a nice GROUPBY command

        Clear(CommentLineCounter);
        if Transaction.FindSet(false) then
            repeat
                if Transaction."Statement No." = '' then begin
                    //Exclude Transactions outside Statement."Trans. Starting Time" and Statement."Trans. Ending Time"
                    TransactionIsOutsideTimeRange := false;
                    if (Statement."Trans. Starting Time" > 0T) and
                       (Transaction.Date = Statement."Trans. Starting Date") and
                       (Transaction.Time < Statement."Trans. Starting Time")
                    then
                        TransactionIsOutsideTimeRange := true;
                    if not TransactionIsOutsideTimeRange then
                        if (Statement."Trans. Ending Time" > 0T) and
                           (Transaction.Date = Statement."Trans. Ending Date") and
                           (Transaction.Time > Statement."Trans. Ending Time")
                        then
                            TransactionIsOutsideTimeRange := true;
                    if not TransactionIsOutsideTimeRange then begin
                        OnBeforeCheckTransaction(Transaction, Statement);

                        if not TmpPOS.Get(Transaction."POS Terminal No.") then begin
                            TmpPOS.Init();
                            TmpPOS."No." := Transaction."POS Terminal No.";
                            TmpPOS.Insert();
                        end;

                        if not TmpTrans.Get('', Transaction."POS Terminal No.", 1) then begin
                            TmpTrans.Init();
                            TmpTrans."Store No." := '';
                            TmpTrans."POS Terminal No." := Transaction."POS Terminal No.";
                            TmpTrans."Transaction No." := 1;
                            TmpTrans.Insert();
                        end;

                        if Transaction."Entry Status" <> Transaction."Entry Status"::Training then begin
                            TmpPOS."Sum of Trans. No." += Transaction."Transaction No.";
                            TmpPOS."Count of Trans." += 1;
                            TmpPOS.Modify();

                            TmpTrans."No. of Item Lines" += Transaction."No. of Item Lines";
                            TmpTrans."No. of Payment Lines" += Transaction."No. of Payment Lines";
                            TmpTrans.Modify();
                        end;

                        if (Transaction."Transaction Type" = Transaction."Transaction Type"::"Tender Decl.") and
                           (Transaction."Entry Status" = Transaction."Entry Status"::" ")
                        then
                            FindLastTenderDecl(Transaction, Store, CurrentStatementRecord."No.");
                        OnAfterCheckTransaction(Transaction, Statement, TmpPOS, TmpTrans);
                    end;
                end;
            until Transaction.Next() = 0;

        // At this stage we have gone through all the transactions within the statement and
        // have summed up the transaction numbers as well as the number of sales and payment
        // lines. We can therefore start the comparison

        if TmpPOS.FindSet(false) then
            repeat
                IsHandled := false;
                OnCheckTmpPOSTransactions(Transaction, Statement, TmpPOS, TmpTrans, ErrorLineCounter, CommentLineCounter, isHandled);
                if not isHandled then begin
                    POSTerminal_Loc.Get(TmpPOS."No.");
                    TmpTrans.Get('', POSTerminal_Loc."No.", 1);
                    if Transaction.GetFilter(Date) <> '' then
                        POSTerminal_Loc.SetFilter("Date Filter", Transaction.GetFilter(Date));
                    POSTerminal_Loc.CalcFields("First Trans. No.", "Last Trans. No.");

                    LastTransaction.Get(POSTerminal_Loc."Store No.", POSTerminal_Loc."No.", POSTerminal_Loc."Last Trans. No.");
                    if (LastTransaction."Transaction Type" <> LastTransaction."Transaction Type"::Logoff) and FuncProfile.RegisterLogonLogoff then
                        InsertComment(
                        Statement."No.", StrSubstNo(LastTransNotLogoff, TmpTrans.TableCaption,
                        POSTerminal_Loc.TableCaption, POSTerminal_Loc."No."), true);

                    if POSTerminal_Loc."First Trans. No." <> 1 then
                        if not FirstTransaction.Get(POSTerminal_Loc."Store No.", POSTerminal_Loc."No.", POSTerminal_Loc."First Trans. No." - 1) then
                            InsertComment(
                            Statement."No.", StrSubstNo(PrevTransMissing, TmpTrans.TableCaption, POSTerminal_Loc."First Trans. No." - 1,
                            Store.TableCaption, POSTerminal_Loc."Store No.", POSTerminal_Loc.TableCaption, POSTerminal_Loc."No."), true);

                    TransCount := POSTerminal_Loc."Last Trans. No." - POSTerminal_Loc."First Trans. No." + 1;
                    TransactionHeaderCount.SetRange("Store No.", POSTerminal_Loc."Store No.");
                    TransactionHeaderCount.SetRange("POS Terminal No.", POSTerminal_Loc."No.");
                    TransactionHeaderCount.SetRange("Transaction No.", POSTerminal_Loc."First Trans. No.", POSTerminal_Loc."Last Trans. No.");
                    TransactionHeaderCount.SetRange("Entry Status", TransactionHeaderCount."Entry Status"::Training);
                    TransTrainCount := TransactionHeaderCount.Count();
                    TransCount := TransCount - TransTrainCount;
                    if TransCount <> TmpPOS."Count of Trans." then
                        InsertComment(
                        Statement."No.", StrSubstNo(EntryMissing, TmpPOS."Count of Trans.", TmpTrans.TableCaption,
                        TmpPOS.TableCaption, TmpPOS."No.", TransCount), true);

                    ItemCount := 0;
                    SalesEntry.Reset();
                    SalesEntry.SetRange("Store No.", POSTerminal_Loc."Store No.");
                    SalesEntry.SetRange("POS Terminal No.", POSTerminal_Loc."No.");
                    SalesEntry.SetRange("Transaction No.", POSTerminal_Loc."First Trans. No.", POSTerminal_Loc."Last Trans. No.");

                    ItemCount := SalesEntry.Count();

                    if ItemCount <> TmpTrans."No. of Item Lines" then
                        InsertComment(
                        Statement."No.", StrSubstNo(SalesEntryMissing, ItemCount, TmpTrans."No. of Item Lines", TmpPOS.TableCaption,
                        TmpPOS."No."), true);

                    PaymentEntry.Reset();
                    PaymentEntry.SetRange("Store No.", POSTerminal_Loc."Store No.");
                    PaymentEntry.SetRange("POS Terminal No.", POSTerminal_Loc."No.");
                    PaymentEntry.SetRange("Transaction No.", POSTerminal_Loc."First Trans. No.", POSTerminal_Loc."Last Trans. No.");
                    PaymentEntryCount := PaymentEntry.Count();
                    if PaymentEntryCount <> TmpTrans."No. of Payment Lines" then
                        InsertComment(
                        Statement."No.", StrSubstNo(EntryMissing, PaymentEntryCount, PaymentEntry.TableCaption, TmpPOS.TableCaption,
                        TmpPOS."No.", TmpTrans."No. of Payment Lines"), true);
                end;
            until TmpPOS.Next() = 0;
        OnAfterCheckTransactions(Transaction, Statement, TmpEndOfDayEntry, ErrorLineCounter, CommentLineCounter);
    end;

    local procedure InsertComment(StatementCode: Code[20]; Comment: Text[250]; IsError: Boolean)
    var
        RetailCommentLine: Record "LSC Retail Comment Line";
        LineNo: Integer;
    begin
        RetailCommentLine.Reset();
        RetailCommentLine.SetRange("Table No.", Database::"LSC Statement");
        RetailCommentLine.SetRange("No.", StatementCode);
        if RetailCommentLine.FindLast() then
            LineNo := RetailCommentLine."Line No." + 1000
        else
            LineNo := 1000;

        RetailCommentLine.Reset();
        RetailCommentLine."Table No." := Database::"LSC Statement";
        RetailCommentLine."No." := StatementCode;
        RetailCommentLine."Line No." := LineNo;
        RetailCommentLine."Comment Date" := Today;
        RetailCommentLine."Comment Time" := Time;
        RetailCommentLine.Code := '';
        RetailCommentLine.Comment := Comment;
        RetailCommentLine."Error Comment" := IsError;
        RetailCommentLine.Insert(true);
        if IsError then
            ErrorLineCounter += 1
        else
            CommentLineCounter += 1;
    end;

    local procedure DeleteWarningComments(StatementCode: Code[20])
    var
        RetailCommentLine: Record "LSC Retail Comment Line";
    begin
        RetailCommentLine.Reset();
        RetailCommentLine.SetRange("Table No.", Database::"LSC Statement");
        RetailCommentLine.SetRange("No.", StatementCode);
        RetailCommentLine.SetRange("Error Comment", true);
        RetailCommentLine.DeleteAll(true);
    end;

    procedure FindLastTenderDecl(TransHeader: Record "LSC Transaction Header"; pStore: Record "LSC Store"; pStatementNo: Code[20])
    var
        EndOfDay: Record "LSC POS Start Status";
        TransactionStatus: Record "LSC Transaction Status";
        lTransTenderDecl: Record "LSC Trans. Tender Declar. Entr";
        lPOSTerminal: Record "LSC POS Terminal";
        lStatementMethod: Option Staff,"POS Terminal",Total;
        InsertEntry: Boolean;
        IsHandled: Boolean;
        ExitProcedure: Boolean;
    begin
        OnBeforeFindLastTenderDecl(TransHeader, pStore, pStatementNo, ExitProcedure, IsHandled);
        if not IsHandled then begin
            lTransTenderDecl.SetRange("Store No.", TransHeader."Store No.");
            lTransTenderDecl.SetRange("POS Terminal No.", TransHeader."POS Terminal No.");
            lTransTenderDecl.SetRange("Transaction No.", TransHeader."Transaction No.");
            if lTransTenderDecl.IsEmpty() then
                exit;  //Exit if no entry is found
        end else
            if ExitProcedure then
                exit;

        if pStore."Safe Mgnt. in Use" then begin
            Clear(EndOfDay);
            EndOfDay."Store No." := TransHeader."Store No.";
            lStatementMethod := pStore."Statement Method";
            if lPOSTerminal.Get(TransHeader."POS Terminal No.") then
                if lPOSTerminal."Terminal Statement" and (lPOSTerminal."Statement Method" <> lStatementMethod) then
                    lStatementMethod := lPOSTerminal."Statement Method";
            case lStatementMethod of
                lStatementMethod::Staff:
                    begin
                        EndOfDay.Type := EndOfDay.Type::Staff;
                        EndOfDay.Id := TransHeader."Staff ID";
                    end;
                lStatementMethod::"POS Terminal":
                    begin
                        EndOfDay.Type := EndOfDay.Type::"POS Terminal";
                        EndOfDay.Id := TransHeader."POS Terminal No.";
                    end;
                else begin
                    EndOfDay.Type := 0;
                    EndOfDay.Id := '';
                end;
            end;

            InsertEntry := true;

            if TransactionStatus.Get(TransHeader."Store No.", TransHeader."POS Terminal No.", TransHeader."Transaction No.") then
                if (TransactionStatus."Statement No." <> '') and (TransactionStatus."Statement No." <> pStatementNo) then
                    InsertEntry := false;

            if InsertEntry then
                if TmpEndOfDayEntry.Get(EndOfDay."Store No.", EndOfDay.Type, EndOfDay.ID) then begin
                    if TmpEndOfDayEntry."Trans. DateTime" < CreateDateTime(TransHeader."Original Date", TransHeader.Time) then begin
                        TmpEndOfDayEntry."Trans. No." := TransHeader."Transaction No.";
                        TmpEndOfDayEntry."Trans. DateTime" := CreateDateTime(TransHeader."Original Date", TransHeader.Time);
                        TmpEndOfDayEntry.Modify();
                    end;
                end else begin
                    TmpEndOfDayEntry."Store No." := EndOfDay."Store No.";
                    TmpEndOfDayEntry.Type := EndOfDay.Type;
                    TmpEndOfDayEntry.Id := EndOfDay.Id;
                    TmpEndOfDayEntry."Trans. No." := TransHeader."Transaction No.";
                    TmpEndOfDayEntry."Trans. DateTime" := CreateDateTime(TransHeader."Original Date", TransHeader.Time);
                    TmpEndOfDayEntry.Insert();
                end;
        end;
    end;

    local procedure IsTransWithEndOfDay(TransHeader: Record "LSC Transaction Header"; Statement: Record "LSC Statement"): Boolean
    var
        EndOfDay: Record "LSC POS Start Status";
        POSTerminal_l: Record "LSC POS Terminal";
        lStatementMethod: Option Staff,"POS Terminal",Total;
        ReturnStat: Boolean;
        Handled: Boolean;
        EndOfDayMissing: Label 'Warning - End of Day Declaration is missing for Store %1, %2 %3';
        NewTransSkipCalc: Label 'Warning - New transactions without End of Day Declaration are not calculated for Store %1, %2 %3';
    begin
        OnBeforeIsTransWithEndOfDay(TransHeader, Statement, Store, ErrorLineCounter, CommentLineCounter, ReturnStat, Handled);
        if Handled then
            exit(ReturnStat);

        POSTerminal_l.Get(TransHeader."POS Terminal No.");
        if Store."Safe Mgnt. in Use" and (not POSTerminal_l."Exclude from Cash Mgnt.") then begin
            Clear(EndOfDay);
            EndOfDay."Store No." := TransHeader."Store No.";
            lStatementMethod := Store."Statement Method";
            if POSTerminal_l."Terminal Statement" and (POSTerminal_l."Statement Method" <> lStatementMethod) then
                lStatementMethod := POSTerminal_l."Statement Method";
            case lStatementMethod of
                lStatementMethod::Staff:
                    begin
                        EndOfDay.Type := EndOfDay.Type::Staff;
                        EndOfDay.Id := TransHeader."Staff ID";
                    end;
                lStatementMethod::"POS Terminal":
                    begin
                        EndOfDay.Type := EndOfDay.Type::"POS Terminal";
                        EndOfDay.Id := TransHeader."POS Terminal No.";
                    end;
                else begin
                    EndOfDay.Type := 0;
                    EndOfDay.Id := '';
                end;
            end;

            if TmpEndOfDayEntry.Get(EndOfDay."Store No.", EndOfDay.Type, EndOfDay.Id) then begin
                if CreateDateTime(TransHeader."Original Date", TransHeader.Time) > TmpEndOfDayEntry."Trans. DateTime" then begin
                    //New Transactions after the first tender declaration are not calculated
                    if not TmpEndOfDayComment.Get(EndOfDay."Store No.", EndOfDay.Type, EndOfDay.Id) then begin
                        TmpEndOfDayComment."Store No." := EndOfDay."Store No.";
                        TmpEndOfDayComment.Type := EndOfDay.Type;
                        TmpEndOfDayComment.Id := EndOfDay.Id;
                        TmpEndOfDayComment.Insert();
                        InsertComment(Statement."No.", StrSubstNo(NewTransSkipCalc, EndOfDay."Store No.", EndOfDay.Type, EndOfDay.Id), true);
                    end;
                    exit(false);
                end;
            end else
                if not TmpEndOfDayComment.Get(EndOfDay."Store No.", EndOfDay.Type, EndOfDay.Id) then begin
                    TmpEndOfDayComment."Store No." := EndOfDay."Store No.";
                    TmpEndOfDayComment.Type := EndOfDay.Type;
                    TmpEndOfDayComment.Id := EndOfDay.Id;
                    TmpEndOfDayComment.Insert();
                    InsertComment(Statement."No.", StrSubstNo(EndOfDayMissing, EndOfDay."Store No.", EndOfDay.Type, EndOfDay.Id), true);
                end;
        end;

        exit(true);
    end;

    procedure GetTenderDeclareEntries(var pTmpEndOfDayEntry: Record "LSC POS Start Status" temporary)
    begin
        pTmpEndOfDayEntry.Copy(TmpEndOfDayEntry, true);
    end;

    local procedure StatementCheckSerialNo(var pStatement: Record "LSC Statement")
    var
        TransactionStatus: Record "LSC Transaction Status";
        TransSalesEntry_Loc: Record "LSC Trans. Sales Entry";
        SerialLotQty: Decimal;
        LotNoInv: Decimal;
        ShouldBePositive: Boolean;
        TransOk: Boolean;
        UpdateTransStatus: Boolean;
        SaleIsReturnSale: Boolean;
    begin
        pStatement.CalcFields("Serial/Lot No. Not Valid");
        if pStatement."Serial/Lot No. Not Valid" > 0 then begin
            TransactionStatus.Reset();
            TransactionStatus.SetCurrentKey("Statement No.", "Blocked Customer", "Sale/Pmt. Difference");
            TransactionStatus.SetRange("Statement No.", pStatement."No.");
            TransactionStatus.SetFilter("Serial/Lot No. Not Valid", '>0');
            TransactionStatus.SetRange(Status, TransactionStatus.Status::" ");
            if TransactionStatus.FindSet() then
                repeat
                    UpdateTransStatus := false;
                    TransSalesEntry_Loc.Reset();
                    TransSalesEntry_Loc.SetRange("Store No.", TransactionStatus."Store No.");
                    TransSalesEntry_Loc.SetRange("POS Terminal No.", TransactionStatus."POS Terminal No.");
                    TransSalesEntry_Loc.SetRange("Transaction No.", TransactionStatus."Transaction No.");
                    TransSalesEntry_Loc.SetRange("Serial/Lot No. Not Valid", true);
                    if TransSalesEntry_Loc.FindSet() then
                        repeat
                            SaleIsReturnSale := TransSalesEntry_Loc.Quantity > 0;
                            if TransSalesEntry_Loc."Serial No." <> '' then begin
                                SerialLotQty := FindStatementSerialLotNoQty(pStatement."No.", TransSalesEntry_Loc);
                                if Abs(SerialLotQty) > 1 then
                                    TransOk := false
                                else begin
                                    ShouldBePositive := NextEntryShouldBePositive(TransSalesEntry_Loc);
                                    if ((SerialLotQty >= 0) and (ShouldBePositive)) or
                                       ((SerialLotQty <= 0) and (not ShouldBePositive))
                                    then
                                        TransOk := true
                                    else
                                        TransOk := false;
                                end;
                                if (not SaleIsReturnSale) and
                                   (TransSalesEntry_Loc."Expiration Date" <> 0D) and (TransSalesEntry_Loc."Expiration Date" < TransSalesEntry_Loc.Date)
                                then
                                    TransOk := false;
                                if TransOk then begin
                                    TransSalesEntry_Loc."Serial/Lot No. Not Valid" := false;
                                    TransSalesEntry_Loc.Modify(true);
                                    TransactionStatus."Serial/Lot No. Not Valid" := TransactionStatus."Serial/Lot No. Not Valid" - 1;
                                    UpdateTransStatus := true;
                                end;
                            end else begin
                                SerialLotQty := FindStatementSerialLotNoQty(pStatement."No.", TransSalesEntry_Loc);
                                LotNoInv := GetSerialLotNoInv(TransSalesEntry_Loc);
                                if (not SaleIsReturnSale) and (-SerialLotQty <= LotNoInv) then
                                    TransOk := true
                                else
                                    TransOk := false;
                                if (not SaleIsReturnSale) and
                                   (TransSalesEntry_Loc."Expiration Date" <> 0D) and (TransSalesEntry_Loc."Expiration Date" < TransSalesEntry_Loc.Date)
                                then
                                    TransOk := false;
                                if TransOk then begin
                                    TransSalesEntry_Loc."Serial/Lot No. Not Valid" := false;
                                    TransSalesEntry_Loc.Modify(true);
                                    TransactionStatus."Serial/Lot No. Not Valid" := TransactionStatus."Serial/Lot No. Not Valid" - 1;
                                    UpdateTransStatus := true;
                                end;
                            end;
                        until TransSalesEntry_Loc.Next() = 0;
                    if UpdateTransStatus then
                        TransactionStatus.Modify(true);
                until TransactionStatus.Next() = 0;
        end;
    end;

    local procedure FindStatementSerialLotNoQty(pStatementNo: Code[20]; var pTransSalesEntry: Record "LSC Trans. Sales Entry"): Decimal
    var
        TransSalesEntryStatus: Record "LSC Trans. Sales Entry Status";
    begin
        TransSalesEntryStatus.Reset();
        TransSalesEntryStatus.SetCurrentKey("Serial No.", "Lot No.", "Store No.", "Item No.", "Variant Code", Status, "Statement No.");
        TransSalesEntryStatus.SetRange("Statement No.", pStatementNo);
        TransSalesEntryStatus.SetRange("Item No.", pTransSalesEntry."Item No.");
        TransSalesEntryStatus.SetRange("Variant Code", pTransSalesEntry."Variant Code");
        if pTransSalesEntry."Serial No." <> '' then
            TransSalesEntryStatus.SetRange("Serial No.", pTransSalesEntry."Serial No.");
        if pTransSalesEntry."Lot No." <> '' then
            TransSalesEntryStatus.SetRange("Lot No.", pTransSalesEntry."Lot No.");
        TransSalesEntryStatus.SetRange(Status, TransSalesEntryStatus.Status::" ");
        TransSalesEntryStatus.CalcSums(Quantity);
        exit(TransSalesEntryStatus.Quantity);
    end;

    local procedure NextEntryShouldBePositive(var pTransSalesEntry: Record "LSC Trans. Sales Entry"): Boolean
    var
        SerialNoInv: Decimal;
    begin
        SerialNoInv := GetSerialLotNoInv(pTransSalesEntry);
        if SerialNoInv > 0 then
            exit(false)
        else
            exit(true);
    end;

    local procedure GetSerialLotNoInv(var pTransSalesEntry: Record "LSC Trans. Sales Entry"): Decimal
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        ReturnValue: Decimal;
        isHandled: Boolean;
    begin
        OnBeforeGetSerialLotNoInv(pTransSalesEntry, ReturnValue, isHandled);
        if isHandled then
            exit(ReturnValue);

        Store.Get(pTransSalesEntry."Store No.");

        ItemLedgerEntry.Reset();
        ItemLedgerEntry.SetCurrentKey("Item No.", Open, "Variant Code", Positive,
          "Location Code", "Posting Date", "Expiration Date", "Lot No.", "Serial No.");
        ItemLedgerEntry.SetRange("Item No.", pTransSalesEntry."Item No.");
        ItemLedgerEntry.SetRange("Variant Code", pTransSalesEntry."Variant Code");
        ItemLedgerEntry.SetRange("Location Code", Store."Location Code");
        if pTransSalesEntry."Serial No." <> '' then
            ItemLedgerEntry.SetRange("Serial No.", pTransSalesEntry."Serial No.");
        if pTransSalesEntry."Lot No." <> '' then
            ItemLedgerEntry.SetRange("Lot No.", pTransSalesEntry."Lot No.");
        ItemLedgerEntry.CalcSums(Quantity);
        exit(ItemLedgerEntry.Quantity);
    end;

    procedure GetSerialLotExpDate(var pTransSalesEntry: Record "LSC Trans. Sales Entry"): Date
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        ExpDate: Date;
        isHandled: Boolean;
    begin
        OnBeforeGetSerialLotExpDate(pTransSalesEntry, ExpDate, isHandled);
        if isHandled then
            exit(ExpDate);
        ExpDate := 0D;

        Store.Get(pTransSalesEntry."Store No.");

        ItemLedgerEntry.Reset();
        ItemLedgerEntry.SetCurrentKey("Item No.", Open, "Variant Code", Positive,
          "Location Code", "Posting Date", "Expiration Date", "Lot No.", "Serial No.");
        ItemLedgerEntry.SetRange("Item No.", pTransSalesEntry."Item No.");
        ItemLedgerEntry.SetRange("Variant Code", pTransSalesEntry."Variant Code");
        ItemLedgerEntry.SetRange("Location Code", Store."Location Code");
        if pTransSalesEntry."Serial No." <> '' then
            ItemLedgerEntry.SetRange("Serial No.", pTransSalesEntry."Serial No.");
        if pTransSalesEntry."Lot No." <> '' then
            ItemLedgerEntry.SetRange("Lot No.", pTransSalesEntry."Lot No.");
        ItemLedgerEntry.SetRange(Open, true);
        ItemLedgerEntry.SetRange(Positive, true);
        if ItemLedgerEntry.FindFirst() then
            ExpDate := ItemLedgerEntry."Expiration Date";

        exit(ExpDate);
    end;

    procedure TransSalesCheckSerialNo(var pTransSalesEntry: Record "LSC Trans. Sales Entry"; var pErrorText: Text[250]): Boolean
    var
        ExpDate: Date;
        SerialNoInv: Decimal;
        SerialNoValid: Boolean;
        SaleIsReturnSale: Boolean;
        lText001: Label 'Serial No. %1 already exists';
        lText002: Label 'Serial No. %1 does not exist';
        lText003: Label 'Serial No. %1 has expired or expiration date is invalid';
    begin
        SerialNoValid := true;
        pErrorText := ' ';
        SaleIsReturnSale := pTransSalesEntry.Quantity > 0;

        if IsItemSNTracking(pTransSalesEntry."Item No.") then begin
            SerialNoInv := GetSerialLotNoInv(pTransSalesEntry);
            if SaleIsReturnSale then begin
                if (SerialNoInv > 0) or (IsSerialNoInTransSalesEntry(pTransSalesEntry)) then begin
                    pErrorText := StrSubstNo(lText001, pTransSalesEntry."Serial No.");
                    SerialNoValid := false;
                end;
            end else
                if (SerialNoInv < 1) or IsSerialNoInTransSalesEntry(pTransSalesEntry) then begin
                    pErrorText := StrSubstNo(lText002, pTransSalesEntry."Serial No.");
                    SerialNoValid := false;
                end else begin
                    ExpDate := GetSerialLotExpDate(pTransSalesEntry);
                    if (ExpDate <> pTransSalesEntry."Expiration Date") or
                       ((pTransSalesEntry."Expiration Date" <> 0D) and (pTransSalesEntry."Expiration Date" < pTransSalesEntry.Date))
                    then begin
                        pErrorText := StrSubstNo(lText003, pTransSalesEntry."Serial No.");
                        SerialNoValid := false;
                    end;
                end;
        end;

        exit(SerialNoValid);
    end;

    internal procedure TransSalesCheckLotNo(var pStatementNo: Code[20]; var pTransSalesEntry: Record "LSC Trans. Sales Entry"; var pErrorText: Text[250]): Boolean
    var
        FirstTransSalesEntry: Record "LSC Trans. Sales Entry";
        LotNoValid: Boolean;
        SaleIsReturnSale: Boolean;
        ExpDate: Date;
        AvailQty, QtyOnPosBeforeCurr : Decimal;
        LotNoInv: Decimal;
        LotOnTransSales: Decimal;
        lText001: Label 'Lot No. %1 does not exist or quantity %2 is not available';
        lText002: Label 'Lot No. %1 has expired or expiration date is invalid';
        recItemLedgEntry: Record "Item Ledger Entry";
        decRemQty: Decimal;
        bolFoundMoreQty: Boolean;
        bolNoMoreRemainingQty: Boolean;
    begin
        LotNoValid := true;
        SaleIsReturnSale := pTransSalesEntry.Quantity > 0;

        if IsItemLotTracking(pTransSalesEntry."Item No.") then begin
            LotNoInv := GetSerialLotNoInv(pTransSalesEntry);
            AvailQty := LotNoInv;
            FirstTransSalesEntry.Reset();
            FirstTransSalesEntry.SetRange("Store No.", pTransSalesEntry."Store No.");
            FirstTransSalesEntry.SetRange("POS Terminal No.", pTransSalesEntry."POS Terminal No.");
            FirstTransSalesEntry.SetRange("Transaction No.", pTransSalesEntry."Transaction No.");
            FirstTransSalesEntry.SetRange("Item No.", pTransSalesEntry."Item No.");
            FirstTransSalesEntry.SetRange("Lot No.", pTransSalesEntry."Lot No.");
            if FirstTransSalesEntry.FindFirst() then;
            if pTransSalesEntry."Line No." > FirstTransSalesEntry."Line No." then begin
                QtyOnPosBeforeCurr := GetSerialLotSalesQty(pTransSalesEntry, pTransSalesEntry."Serial No.", pTransSalesEntry."Lot No.", true);
                AvailQty := LotNoInv - QtyOnPosBeforeCurr;
            end;
            //!!!
            //Message('TransSalesCheckLotNo\AvailQty: %1\LotNoInv: %2\QtyOnPosBeforeCurr: %3\Item No. %4', AvailQty, LotNoInv, QtyOnPosBeforeCurr, pTransSalesEntry."Item No.");
            LotOnTransSales := -FindStatementSerialLotNoQty(pStatementNo, pTransSalesEntry);
            if not SaleIsReturnSale then
                if AvailQty < (LotOnTransSales - pTransSalesEntry.Quantity) then begin
                    pErrorText := StrSubstNo(lText001, pTransSalesEntry."Lot No.", -pTransSalesEntry.Quantity);

                    recItemLedgEntry.Reset();
                    recItemLedgEntry.SetRange("Location Code", pTransSalesEntry."Store No.");
                    recItemLedgEntry.SetRange("Item No.", pTransSalesEntry."Item No.");
                    recItemLedgEntry.SetRange("Lot No.", pTransSalesEntry."Lot No.");

                    bolNoMoreRemainingQty := false;
                    if recItemLedgEntry.FindFirst() then
                        if recItemLedgEntry."Remaining Quantity" < ABS(pTransSalesEntry.Quantity) then
                            bolNoMoreRemainingQty := true;

                    if bolNoMoreRemainingQty then begin
                        recItemLedgEntry.Reset();
                        recItemLedgEntry.SetRange("Location Code", pTransSalesEntry."Store No.");
                        recItemLedgEntry.SetRange("Item No.", pTransSalesEntry."Item No.");
                        recItemLedgEntry.SetFilter("Remaining Quantity", '>%1', ABS(pTransSalesEntry.Quantity));
                        decRemQty := 0;
                        bolFoundMoreQty := false;
                        if recItemLedgEntry.FindFirst() then
                            repeat
                                if recItemLedgEntry."Remaining Quantity" > pTransSalesEntry.Quantity then begin
                                    pTransSalesEntry."Original Lot No." := pTransSalesEntry."Lot No.";
                                    pTransSalesEntry."Lot No." := recItemLedgEntry."Lot No.";
                                    pTransSalesEntry.Modify();
                                    bolFoundMoreQty := true;
                                end;
                            until (recItemLedgEntry.Next() = 0) OR (bolFoundMoreQty = true);

                        if not bolFoundMoreQty then
                            LotNoValid := false;
                    end;
                    //TEMPONLY //LotNoValid := false;
                    //!!!
                    //Message('Item No. %5\AvailQty: %1 < (LotOnTransSales: %2 - pTransSalesEntry.Quantity: %3)\Difference %4', AvailQty, LotOnTransSales, pTransSalesEntry.Quantity, Format(LotOnTransSales - pTransSalesEntry.Quantity), pTransSalesEntry."Item No.");
                end else begin
                    if not GetStrictExpirationPosting(pTransSalesEntry."Item No.") then
                        exit(LotNoValid);

                    ExpDate := GetSerialLotExpDate(pTransSalesEntry);
                    if (ExpDate <> pTransSalesEntry."Expiration Date") or
                       ((pTransSalesEntry."Expiration Date" <> 0D) and (pTransSalesEntry."Expiration Date" < pTransSalesEntry.Date))
                    then begin
                        pErrorText := StrSubstNo(lText002, pTransSalesEntry."Lot No.");
                        LotNoValid := false;
                    end;
                end;
        end;

        exit(LotNoValid);
    end;

    internal procedure GetSerialLotSalesQty(var pTransSalesEntry: Record "LSC Trans. Sales Entry"; pSerialNo: Code[50]; pLotNo: Code[50]; BeforeCurr: Boolean): Decimal
    var
        TransSalesEntry: Record "LSC Trans. Sales Entry";
        QtyOnPos: Decimal;
    begin
        QtyOnPos := 0;

        TransSalesEntry.Reset();
        TransSalesEntry.SetRange("Variant Code", pTransSalesEntry."Variant Code");
        TransSalesEntry.SetRange("Store No.", pTransSalesEntry."Store No.");
        TransSalesEntry.SetRange("Item No.", pTransSalesEntry."Item No.");
        TransSalesEntry.SetRange("Unit of Measure", pTransSalesEntry."Unit of Measure");
        if BeforeCurr then
            TransSalesEntry.SetFilter("Line No.", '<%1', pTransSalesEntry."Line No.");
        if pSerialNo <> '' then
            TransSalesEntry.SetRange("Serial No.", pSerialNo);
        if pLotNo <> '' then
            TransSalesEntry.SetRange("Lot No.", pLotNo);
        if TransSalesEntry.FindSet() then
            repeat
                TransSalesEntry.Quantity := -TransSalesEntry.Quantity;
                QtyOnPos := QtyOnPos + TransSalesEntry.Quantity;
            until TransSalesEntry.Next() = 0;

        exit(QtyOnPos);
    end;

    local procedure CheckMissingTransFromPOS(Statement: Record "LSC Statement")
    var
        DistLocation: Record "LSC Distribution Location";
        POSTerminalLocal: Record "LSC POS Terminal";
        GetLastTransNoForPosUtils: Codeunit LSCGetLastTransNoForPosUtils;
        POSDialog: Dialog;
        ResponseCode: Code[30];
        ErrorMessage: Text;
        Diff: Integer;
        MaxTransNo: Integer;
        POSDialogTxt: Label 'Checking for %1 on %2  #3##########';
        CheckOK: Label '%1 %2 is OK - last %3 number is %4';
        MissingTrans: Label '%1 %2 missing from %3 %4. Last %2 on %4 is %5 - last local %2 is %6';
        EndCheck: Label 'Done checking for Transactions on POS';
        StartCheck: Label 'Start checking for Transactions on POS';
    begin
        // This function connects to the POS terminals in the statement and checks if there are transactions
        // on the POS that have not been replicated to the HO.
        Store.Get(Statement."Store No.");
        POSTerminalLocal.SetRange("Store No.", Store."No.");
        if not POSTerminalLocal.FindFirst() then
            exit;

        GetLocalTrans();
        LastCommentNo := FindLastComment(Statement);
        InsertComment(Statement."No.", StartCheck, false);
        CommentLineCounter -= 1;

        if GuiAllowed then
            POSDialog.Open(StrSubstNo(POSDialogTxt, Transaction.TableCaption, POSTerminal.TableCaption));

        repeat
            if GuiAllowed then
                POSDialog.Update(3, POSTerminal."No.");
            if POSTerminalLocal."Functionality Profile" = '' then
                POSTerminalLocal."Functionality Profile" := Store."Functionality Profile";

            if DistLocation.Get(POSTerminalLocal."No.") then
                if DistLocation."Active for Replication" then begin
                    GetLastTransNoForPosUtils.SendRequestV2(POSTerminalLocal."No.", DistLocation, ResponseCode, ErrorMessage, MaxTransNo);
                    GetLastTransNoForPosUtils.SetCommunicationError(ResponseCode, ErrorMessage);
                    if ErrorMessage = '' then begin
                        POSTerminalTemp2.Get(POSTerminalLocal."No.");
                        if MaxTransNo <> POSTerminalTemp2."AutoLogoff After (Min.)" then begin
                            Diff := MaxTransNo - POSTerminalTemp2."AutoLogoff After (Min.)";
                            InsertComment(
                              Statement."No.",
                              StrSubstNo(
                              MissingTrans, Diff, Transaction.TableCaption,
                              POSTerminalLocal.TableCaption, POSTerminalLocal."No.",
                              MaxTransNo, POSTerminalTemp2."AutoLogoff After (Min.)"), true);
                        end else begin
                            InsertComment(
                              Statement."No.",
                              StrSubstNo(CheckOK, POSTerminalLocal.TableCaption, POSTerminalLocal."No.", Transaction.TableCaption, MaxTransNo), false);
                            CommentLineCounter -= 1;
                        end;
                    end else
                        InsertComment(Statement."No.", ResponseCode + ': ' + ErrorMessage, true);
                end;
        until POSTerminalLocal.Next() = 0;

        if GuiAllowed then
            POSDialog.Close();

        InsertComment(Statement."No.", EndCheck, false);
        CommentLineCounter -= 1;
    end;

    local procedure FindLastComment(Statement: Record "LSC Statement"): Integer
    var
        RetailCommentLine: Record "LSC Retail Comment Line";
    begin
        // Find the last comment line before the check so we know which lines to display after the check

        RetailCommentLine.SetRange("Table No.", Database::"LSC Statement");
        RetailCommentLine.SetRange("No.", Statement."No.");
        if RetailCommentLine.FindLast() then
            exit(RetailCommentLine."Line No.")
        else
            exit(0);
    end;

    local procedure GetLocalTrans()
    var
        TransactionLocal: Record "LSC Transaction Header";
    begin
        // Find the highest transaction numbers in the local database for each POS

        POSTerminalTemp2.Reset();
        POSTerminalTemp2.DeleteAll();

        POSTerminal.SetRange("Store No.", Store."No.");
        if POSTerminal.FindSet() then
            repeat
                POSTerminalTemp2."No." := POSTerminal."No.";

                TransactionLocal.SetRange("Store No.", POSTerminal."Store No.");
                TransactionLocal.SetRange("POS Terminal No.", POSTerminal."No.");
                if TransactionLocal.FindLast() then
                    POSTerminalTemp2."AutoLogoff After (Min.)" := TransactionLocal."Transaction No."
                else
                    POSTerminalTemp2."AutoLogoff After (Min.)" := 0;
                POSTerminalTemp2.Insert();
            until POSTerminal.Next() = 0;
    end;

    local procedure OpenTablesBuffers()
    var
        TransactionStatus: Record "LSC Transaction Status";
        TransSalesEntryStatus: Record "LSC Trans. Sales Entry Status";
        TransSalesEntry: Record "LSC Trans. Sales Entry";
        RecRef: RecordRef;
    begin
        RecRef.GETTABLE(TransactionStatus);
        if BufferUtility.IsBufferOpen(RecRef, 1) then
            BufferUtility.CloseBuffer(RecRef, 1);
        BufferUtility.OpenBuffer(RecRef, 1);

        RecRef.GETTABLE(TransSalesEntryStatus);
        if BufferUtility.IsBufferOpen(RecRef, 1) then
            BufferUtility.CloseBuffer(RecRef, 1);
        BufferUtility.OpenBuffer(RecRef, 1);

        RecRef.GETTABLE(TransSalesEntry);
        if BufferUtility.IsBufferOpen(RecRef, 1) then
            BufferUtility.CloseBuffer(RecRef, 1);
        BufferUtility.OpenBuffer(RecRef, 1);
    end;

    local procedure FlushTablesBuffers()
    var
        TransactionStatus: Record "LSC Transaction Status";
        TransSalesEntryStatus: Record "LSC Trans. Sales Entry Status";
        TransSalesEntry: Record "LSC Trans. Sales Entry";
        TransactionStatusTmp: Record "LSC Transaction Status" temporary;
        TransSalesEntryStatusTmp: Record "LSC Trans. Sales Entry Status" temporary;
        TransSalesEntryTmp: Record "LSC Trans. Sales Entry" temporary;
        RecRef: RecordRef;
    begin
        RecRef.GetTable(TransactionStatusTmp);
        BufferUtility.SetTableFilter(1, RecRef, 1);
        if BufferUtility.FindFirstRec(1, RecRef, 1) then
            repeat
                RecRef.SetTable(TransactionStatusTmp);
                if TransactionStatus.Get(TransactionStatusTmp."Store No.", TransactionStatusTmp."POS Terminal No.", TransactionStatusTmp."Transaction No.") then begin
                    TransactionStatus.TransferFields(TransactionStatusTmp, false);
                    TransactionStatus.Modify(true);
                end else begin
                    TransactionStatus.Init();
                    TransactionStatus := TransactionStatusTmp;
                    TransactionStatus.Insert(true);
                end;
            until BufferUtility.NextRec(1, 1, RecRef, 1) = 0;
        RecRef.GetTable(TransactionStatusTmp);
        BufferUtility.CloseBuffer(RecRef, 1);

        RecRef.GetTable(TransSalesEntryStatusTmp);
        BufferUtility.SetTableFilter(1, RecRef, 1);
        if BufferUtility.FindFirstRec(1, RecRef, 1) then
            repeat
                RecRef.SetTable(TransSalesEntryStatusTmp);
                if TransSalesEntryStatus.Get(TransSalesEntryStatusTmp."Store No.", TransSalesEntryStatusTmp."POS Terminal No.", TransSalesEntryStatusTmp."Transaction No.",
                TransSalesEntryStatusTmp."Line No.")
                then begin
                    TransSalesEntryStatus.TransferFields(TransSalesEntryStatusTmp, false);
                    TransSalesEntryStatus.Modify(true);
                end else begin
                    TransSalesEntryStatus.Init();
                    TransSalesEntryStatus := TransSalesEntryStatusTmp;
                    TransSalesEntryStatus.Insert(true);
                end;
            until BufferUtility.NextRec(1, 1, RecRef, 1) = 0;
        RecRef.GetTable(TransSalesEntryStatusTmp);
        BufferUtility.CloseBuffer(RecRef, 1);

        RecRef.GetTable(TransSalesEntryTmp);
        BufferUtility.SetTableFilter(1, RecRef, 1);
        if BufferUtility.FindFirstRec(1, RecRef, 1) then
            repeat
                RecRef.SetTable(TransSalesEntryTmp);
                if TransSalesEntry.Get(TransSalesEntryTmp."Store No.", TransSalesEntryTmp."POS Terminal No.", TransSalesEntryTmp."Transaction No.",
                TransSalesEntryTmp."Line No.")
                then begin
                    TransSalesEntry.TransferFields(TransSalesEntryTmp, false);
                    TransSalesEntry.Modify(true);
                end else begin
                    TransSalesEntry.Init();
                    TransSalesEntry := TransSalesEntryTmp;
                    TransSalesEntry.Insert(true);
                end;
            until BufferUtility.NextRec(1, 1, RecRef, 1) = 0;
        RecRef.GetTable(TransSalesEntryTmp);
        BufferUtility.CloseBuffer(RecRef, 1);
    end;

    local procedure TransStatusToBuffer(var TransactionStatus: Record "LSC Transaction Status")
    var
        RecRef: RecordRef;
    begin
        RecRef.GetTable(TransactionStatus);
        BufferUtility.UpdateRec(RecRef, 1);
    end;

    local procedure TransSalesEntryStatusToBuffer(var TransSalesEntryStatus: Record "LSC Trans. Sales Entry Status")
    var
        RecRef: RecordRef;
    begin
        RecRef.GetTable(TransSalesEntryStatus);
        BufferUtility.UpdateRec(RecRef, 1);
    end;

    local procedure TransSalesEntryToBuffer(var TransSalesEntry: Record "LSC Trans. Sales Entry")
    var
        RecRef: RecordRef;
    begin
        RecRef.GetTable(TransSalesEntry);
        BufferUtility.UpdateRec(RecRef, 1);
    end;

    local procedure GetTransStatusFromBuffer(var Transaction: Record "LSC Transaction Header"; var TransactionStatus: Record "LSC Transaction Status")
    var
        RecRef: RecordRef;
        lText001: Label 'Record not found %1';
    begin
        TransactionStatus."Store No." := Transaction."Store No.";
        TransactionStatus."POS Terminal No." := Transaction."POS Terminal No.";
        TransactionStatus."Transaction No." := Transaction."Transaction No.";
        RecRef.GetTable(TransactionStatus);
        if not BufferUtility.GetRec(RecRef, 1) then
            Error(lText001, TransactionStatus.RecordId);
        RecRef.SetTable(TransactionStatus);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeRunCodeunit(var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterRunCodeunit(var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCalcByDateTime(var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCalcByDateTime(var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCalcByShift(var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCalcByShift(var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeMarkTransaction(var TransactionHeader: Record "LSC Transaction Header"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterMarkTransaction(var TransactionHeader: Record "LSC Transaction Header"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeProcessTransaction(var TransactionHeader: Record "LSC Transaction Header"; Statement: Record "LSC Statement"; var IsHandled: Boolean; var ReturnValue: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterProcessTransaction(var TransactionHeader: Record "LSC Transaction Header"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckTransaction(var TransactionHeader: Record "LSC Transaction Header"; var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCheckTransaction(var TransactionHeader: Record "LSC Transaction Header"; var Statement: Record "LSC Statement"; var TmpPOS: Record "LSC POS Terminal" temporary; var TmpTrans: Record "LSC Transaction Header" temporary)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeInsertStatementLine(var StatementLine: Record "LSC Statement Line"; Store: Record "LSC Store"; POSTerminal: Record "LSC POS Terminal")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeIsTransWithEndOfDay(var TransactionHeader: Record "LSC Transaction Header"; var Statement: Record "LSC Statement"; Store: Record "LSC Store"; var ErrorLineCounter: Integer; var CommentLineCounter: Integer; var ReturnStat: Boolean; var Handled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnUpdateReferenceNumber(TempLSCTransTenderDeclarEntr: Record "LSC Trans. Tender Declar. Entr" temporary; var LSCStatementLine: Record "LSC Statement Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnMarkTransOnBeforeTransSalesEntryStatusToBuffer(var TransSalesEntryStatus: Record "LSC Trans. Sales Entry Status")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeUpdateTransSalesEntryOfMarkTransaction(var TransSalesEntry: Record "LSC Trans. Sales Entry"; var UpdateTransSalesEntry: Boolean; StatementNo: Code[20])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeTransStatusToBufferOfMarkTransaction(var TransTenderDeclarEntry: Record "LSC Trans. Tender Declar. Entr"; StatementNo: Code[20])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCalculateStatementLine2TransAmount(TransPmtEntry: Record "LSC Trans. Payment Entry"; var StatementLine2: Record "LSC Statement Line"; var LastCurr: Code[10]);
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCalcStatementLine2TransAmout(TransPmtEntry: Record "LSC Trans. Payment Entry"; var StatementLine2: Record "LSC Statement Line");
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeValidateStatementLineTenderTypeName(var Statement: Record "LSC Statement"; var LastCurr: Code[10]; var StatementLine: Record "LSC Statement Line");
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeValidateSafeStatemetLineDescription(var SafeStatementLine: Record "LSC Safe Statement Line");
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterSetTransactionsFree(var Statement: Record "LSC Statement");
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeInsertSafeStatemetLine(Statement: Record "LSC Statement"; var SafeStatementLine: Record "LSC Safe Statement Line"; TrSafeEntry: Record "LSC Trans. Safe Entry");
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCheckTransactions(var Transaction: Record "LSC Transaction Header"; var Statement: Record "LSC Statement"; var TmpEndOfDayEntry: Record "LSC POS Start Status" temporary; var ErrorLineCounter: Integer; var CommentLineCounter: Integer)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnCheckTmpPOSTransactions(var Transaction: Record "LSC Transaction Header"; var Statement: Record "LSC Statement"; var TmpPOS: Record "LSC POS Terminal" temporary; var TmpTrans: Record "LSC Transaction Header" temporary; var ErrorLineCounter: Integer; var CommentLineCounter: Integer; var isHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterModifyInsertTmpDeclEntry(var Statement: Record "LSC Statement"; var Store: Record "LSC Store"; var TmpDeclEntry: Record "LSC Trans. Tender Declar. Entr" temporary; TransTenderDeclarEntry: Record "LSC Trans. Tender Declar. Entr")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGetSerialLotNoInv(var pTransSalesEntry: Record "LSC Trans. Sales Entry"; var ReturnValue: Decimal; var isHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGetSerialLotExpDate(var pTransSalesEntry: Record "LSC Trans. Sales Entry"; var ReturnValue: Date; var isHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCalcAmountToBeRefunded(var TransIncomeExpenseEntry: Record "LSC Trans. Inc./Exp. Entry"; var TransactionStatus: Record "LSC Transaction Status"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindLastTenderDecl(TransHeader: Record "LSC Transaction Header"; pStore: Record "LSC Store"; pStatementNo: Code[20]; var ExitProcedure: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnCheckLotNo(TransSalesEntryPAR: Record "LSC Trans. Sales Entry"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeShowErrorLineCounter(ErrorLineCounter: Integer; Var IsHandled: Boolean);
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterGetTransStatusFromBuffer(StatementNo: Code[20]; var TransactionHeader: Record "LSC Transaction Header"; var TransactionStatus: Record "LSC Transaction Status");
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCalculateIncExpAmounts(var TransIncomeExpenseEntry: Record "LSC Trans. Inc./Exp. Entry");
    begin
    end;
}