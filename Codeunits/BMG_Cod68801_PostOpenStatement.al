codeunit 68801 "BMG LSC Statement-Post"// implements "LSC IStatementPostController"
{
    Permissions = TableData "G/L Account" = r,
                  TableData Customer = r,
                  TableData "Gen. Journal Line" = rimd,
                  TableData "Item Journal Line" = rimd,
                  TableData "General Ledger Setup" = r,
                  TableData "Sales Shipment Header" = rm,
                  TableData "General Posting Setup" = r,
                  TableData "LSC Item Posting Buffer V2" = rimd,
                  TableData "LSC Ledger Posting Buffer" = rimd,
                  TableData "LSC Tender Type" = r,
                  TableData "LSC Store" = r,
                  TableData "LSC Transaction Header" = rm,
                  TableData "LSC Trans. Sales Entry" = rm,
                  TableData "LSC Trans. Payment Entry" = rm,
                  TableData "LSC Trans. Inc./Exp. Entry" = rm,
                  TableData "LSC Income/Expense Account" = r,
                  TableData "LSC Trans. Infocode Entry" = rm,
                  TableData "LSC Posted Statement" = rimd,
                  TableData "LSC Scheduler Setup" = r,
                  TableData "LSC Statement" = rm,
                  TableData "LSC Statement Line" = rm,
                  TableData "LSC Posted Statement Line" = rimd,
                  TableData "LSC Trans. Inventory Entry" = r,
                  TableData "LSC Tender TP Card No. Series" = r,
                  TableData "LSC Work Shift RBO" = rimd,
                  TableData "LSC Work Shift Entry" = rimd;
    TableNo = "LSC Statement";

    trigger OnRun()
    var
        ItemPostingBuffer_RV: Record "LSC Item Posting Buffer V2";
        ItemPostingBuffer_Temp: Record "LSC Item Posting Buffer V2";
        ReplenSetup: Record "LSC Replen. Setup";
        PostedCashDeclaration: Record "LSC Posted Cash Declaration";
        DimVal: Record "Dimension Value";
        MealPlanningSetup: Record "LSC Meal Planning Setup";
        TransDiscEntryTemp: Record "LSC Trans. Discount Entry" temporary;
        SafePost: Codeunit "LSC Safe Statement-Post";
        CommissionUtils: Codeunit "LSC Commission Utility";
        ReplenishmUpdLikeForLike: Codeunit "LSC Replen. Upd Like-for-Like";
        StatisticsUtils: Codeunit "LSC Statistics Utils";
        UpdateAnalysisView: Codeunit "Update Analysis View";
        SessionKeyValues: Codeunit "LSC Session Key Values";
        SchedulerUtil: Codeunit "LSC Scheduler Util";
        GenJnlPostPreview: Codeunit "Gen. Jnl.-Post Preview";
        CodeDictionary_l: Dictionary of [Integer, Code[20]];
        DimSource_l: List of [Dictionary of [Integer, Code[20]]];
        DocumentNo: Code[20];
        Description: Text;
        CurrencyGainLoss: Decimal;
        PrepaymentInvoiceAmount: Decimal;
        PrepaymentInvoiceVATBaseAmount: Decimal;
        PrepaymentInvoiceVATAmount: Decimal;
        BOMLineNo: Integer;
        Sign: Integer;
        IsHandled: Boolean;
        AccountNo: Code[20];
        AccountType: Enum "Gen. Journal Account Type";
        PostTransactionAsShipment: Boolean;
        VATReverseLabel: Label 'VAT Reversed';
        Text040: Label 'Marking Headers as posted';
        Text039: Label 'Posting Sales To Stock';
        Text038: Label 'Rounding Amount %1 is higher than %2 - %3 in %4 %5.';
        Text037: Label 'Posting Rounding Difference';
        Text036: Label 'Type %1 \ PostGr %2 PostGr2 %3 \ Amount %4 \ L Disc %5 \ Inv disc %6';
        Text035: Label 'Posting Sales To G/L ';
        Text034: Label 'Statement difference ';
        Text033: Label 'Posting statement lines';
        Text030: Label '%1 %2 is already Posted.';
        Text015: Label '   Posting Statement #1##################\\\';
        Text016: Label ' Buffering Dimensions....\';
        Text017: Label '    Transactions          #11################# \';
        Text018: Label '    Sales Entries         #12################# \\\';
        Text019: Label ' Transactions....\';
        Text020: Label '    Receipt No.           #2################## \';
        Text021: Label '    Line                  #3##################\\\';
        Text022: Label ' Posting......\';
        Text023: Label '    Statement Line        #4################## \';
        Text024: Label '    Posting Sales To G/L  #5################## \';
        Text025: Label '    Updating stock        #6################## \\\';
        Text026: Label ' Marking Transactions\';
        Text027: Label '    Headers               #7################## \';
        Text028: Label '    Sales Lines           #8################## \';
        Text029: Label '    Payment Lines         #9################## \\\';
        Text060: Label 'Posting Inv. Adjust.';
        Text059: Label 'Unable to post %1 %2.\Some %3 and/or %4 are missing.  Run the "Check Transactions" function for detailed information';
        Text056: Label 'Return Orders %1 to %2 have been created. They need to be received.';
        Text055: Label 'Return Order %1 has been created. It needs to be received.';
        Text051: Label 'Posting BOM To Stock';
        Text050: Label 'Updating BOM Cost';
        Text046: Label 'Posting Negative Adjustment';
    begin
        LockTimeout(false);

        OnBeforeStatementPost(Rec, IsHandled);
        if IsHandled then
            exit;

        if not PreviewMode then
            if not RunningFromBatchPosting then
                ClearAll();
        if not MealPlanningSetup.Get() then
            Clear(MealPlanningSetup);

        ItemPostingBuffer[1].DeleteAll();
        ItemBuffer.DeleteAll();
        PostingBuffer[1].DeleteAll();
        BOMPostingBuffer[1].DeleteAll();
        BOMItemBuffer.DeleteAll();
        ItemAdjustPostBuffer[1].DeleteAll();
        TransPostingFunctions.InitFunction();
        Clear(RetailBOMJnlPostLine);
        Clear(ItemJnlPostLine);
        Clear(DiscLedgerMgt);

        Statement := Rec;
        BackOfficeSetup.Get();
        BackOfficeSetup.TestField("Source Code");
        SchedulerSetup.Get();

        SalesReceivablesSetup.Get();
        Rec.TestField("Posting Date");

        Rec.TestField("Store No.");
        Store.Get(Rec."Store No.");
        Store.TestField("Gen. Bus. Post. Gr.");
        GenLedgerSetup.Get();
        CompletePost := true;

        if not RunningFromBatchPosting then
            "Cust/ItemChecks"(Statement, TRUE);
        PrePostingChecks(Statement, Store, RunningFromBatchPosting);

        if not Statement.Debugmode then
            Win.HideSubsequentDialogs(true);
        Win.Open(
          Text015 +
          Text016 +
          Text017 +
          Text018 +
          Text019 +
          Text020 +
          Text021 +
          Text022 +
          Text023 +
          Text024 +
          Text025 +
          Text026 +
          Text027 +
          Text028 +
          Text029 +
          ' #10################################ ');

        if not Statement.Debugmode then
            Win.Update(1, Rec."No.");
        Transaction.Reset();
        TransSalesEntry.Reset();
        TransPmtEntry.Reset();
        TransIncomeExpenseEntry.Reset();
        TransInfocodeEntry.Reset();
        TransInventoryEntry.Reset();

        if Rec."Posting No." = '' then begin
            Rec.TestField("Posting Nos.");
            if Rec."Posting Nos." <> Rec."No. Series." then
                Rec."Posting No." := NoSeries.GetNextNo(Rec."Posting Nos.", Rec."Posting Date", true)
            else
                Rec."Posting No." := Rec."No.";
            Rec.Modify();
            Statement."Posting No." := Rec."Posting No.";
        end;

        CalculateTransactionDiscounts(TransDiscEntryTemp, Rec."No.");
        OpenTablesBuffers();
        TransactionStatus.Reset();
        TransactionStatus.SetCurrentKey("Statement No.");
        TransactionStatus.SetRange("Statement No.", Rec."No.");
        if TransactionStatus.FindSet() then
            repeat
                OnBeforeProcessTransactionStatus(TransactionStatus, Statement);
                if TransactionStatus.Status = TransactionStatus.Status::Posted then
                    Error(Text030, Rec.FieldCaption("No."), Rec."No.");
                Transaction.Get(TransactionStatus."Store No.", TransactionStatus."POS Terminal No.", TransactionStatus."Transaction No.");
                if Transaction."Transaction Type" = Transaction."Transaction Type"::Sales then
                    if not CheckTransSubTables(Transaction) then
                        Error(Text059, Rec.TableCaption, Rec."No.", TransSalesEntry.TableCaption, TransPmtEntry.TableCaption);
                if not Statement.Debugmode then
                    Win.Update(2, Transaction."Receipt No.");

                If Transaction."To Account" then begin
                    if not CustomerRec.Get(Transaction."Customer No.") then
                        Error(
                          Text031,
                          Transaction.FieldCaption("Customer No."), Transaction."Customer No.", CustomerRec.TableCaption);
                    TransSalesEntry.SetRange("Store No.", Transaction."Store No.");
                    TransSalesEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                    TransSalesEntry.SetRange("Transaction No.", Transaction."Transaction No.");
                    PostTransactionAsShipment := Transaction."Post as Shipment";
                    OnBeforeCheckPostTransactionAsShipment(Transaction, PostTransactionAsShipment);
                    if PostTransactionAsShipment then begin
                        SessionKeyValues.SetValue('OrderFromStatement', 'TRUE');
                        MakeOrder(TransDiscEntryTemp, true);
                        SessionKeyValues.SetValue('OrderFromStatement', 'FALSE');
                    end else
                        if TransSalesEntry.FindSet() then
                            repeat
                                DocumentNo := CreateDocNo(TransSalesEntry."Store No.",
                                  TransSalesEntry."POS Terminal No.",
                                  TransSalesEntry."Transaction No.");
                                PostItemSales(TransDiscEntryTemp, DocumentNo, true);
                            until TransSalesEntry.Next() = 0;

                    TransInfocodeEntry.SetRange("Store No.", Transaction."Store No.");
                    TransInfocodeEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                    TransInfocodeEntry.SetRange("Transaction No.", Transaction."Transaction No.");
                    TransInfocodeEntry.SetRange("Transaction Type", TransInfocodeEntry."Transaction Type"::"Payment Entry");
                    TransInfocodeEntry.SetRange("Type of Input", TransInfocodeEntry."Type of Input"::"Apply To Entry");
                    if TransInfocodeEntry.FindSet() then
                        repeat
                            DocumentNo := CreateDocNo(TransInfocodeEntry."Store No.",
                              TransInfocodeEntry."POS Terminal No.",
                              TransInfocodeEntry."Transaction No.");
                            PostDataEntryReverseVAT(DocumentNo);
                        until TransInfocodeEntry.Next() = 0;

                    TransIncomeExpenseEntryBuffer.Reset();
                    TransIncomeExpenseEntryBuffer.DeleteAll();

                    if (PostTransactionAsShipment and not CustomerRec."LSC Incl. Inc/Exp on Sales Doc") or
                        not PostTransactionAsShipment or
                        Transaction."Customer Order"
                    then begin
                        TransIncomeExpenseEntry.Reset();
                        TransIncomeExpenseEntry.SetRange("Store No.", Transaction."Store No.");
                        TransIncomeExpenseEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                        TransIncomeExpenseEntry.SetRange("Transaction No.", Transaction."Transaction No.");
                        if TransIncomeExpenseEntry.FindSet() then begin
                            repeat
                                DocumentNo := CreateDocNo(TransIncomeExpenseEntry."Store No.",
                                  TransIncomeExpenseEntry."POS Terminal No.",
                                  TransIncomeExpenseEntry."Transaction No.");
                                PostIncomeExpLine(DocumentNo);
                            until TransIncomeExpenseEntry.Next() = 0;
                            //!!!
                            if COPrepaymentInvoiceMan.IsCustomerOrderPrepaymentInvoiceMarked(Transaction."Customer Order ID") then
                                if CollectionBySalesOrder(Transaction."Customer Order ID") then begin
                                    PostingBuffer[1].Reset();
                                    PostingBuffer[1].SetRange("Customer Order ID", Transaction."Customer Order ID");
                                    PostingBuffer[1].SetRange("Document No.", DocumentNo);
                                    if PostingBuffer[1].FindFirst() then
                                        if Transaction.Payment > 0 then begin
                                            PrepaymentInvoiceAmount := Transaction.Payment + Transaction."Gross Amount" - Transaction."Amount to Account";
                                            if PrepaymentInvoiceAmount < 0 then
                                                PostingBuffer[1].Delete()
                                            else begin
                                                PrepaymentInvoiceVATBaseAmount := PrepaymentInvoiceAmount / (1 + (IncExpVATPercent / 100));
                                                PrepaymentInvoiceVATAmount := PrepaymentInvoiceAmount - PrepaymentInvoiceVATBaseAmount;
                                                PostingBuffer[1]."VAT Base Amount" := -PrepaymentInvoiceVATBaseAmount;
                                                PostingBuffer[1].Amount := PostingBuffer[1]."VAT Base Amount";
                                                PostingBuffer[1]."VAT Amount" := -PrepaymentInvoiceVATAmount;
                                                PostingBuffer[1].Modify();
                                            end;
                                        end;
                                end;

                        end;
                    end;

                    if TransactionStatus."Customer Order ID" <> '' then
                        PostCOAmountToBeRefunded(Rec."Posting No.");

                    DocumentNo := CreateDocNo(Transaction."Store No.",
                      Transaction."POS Terminal No.",
                      Transaction."Transaction No.");
                    PostToCustomer(DocumentNo);
                end else begin
                    TransSalesEntry.SetRange("Store No.", Transaction."Store No.");
                    TransSalesEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                    TransSalesEntry.SetRange("Transaction No.", Transaction."Transaction No.");
                    if TransSalesEntry.FindSet() then
                        repeat
                            PostItemSales(TransDiscEntryTemp, Rec."Posting No.", true);
                        until TransSalesEntry.Next() = 0;

                    TransInfocodeEntry.SetRange("Store No.", Transaction."Store No.");
                    TransInfocodeEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                    TransInfocodeEntry.SetRange("Transaction No.", Transaction."Transaction No.");
                    TransInfocodeEntry.SetRange("Transaction Type", TransInfocodeEntry."Transaction Type"::"Payment Entry");
                    TransInfocodeEntry.SetRange("Type of Input", TransInfocodeEntry."Type of Input"::"Apply To Entry");
                    if TransInfocodeEntry.FindSet() then
                        repeat
                            PostDataEntryReverseVAT(Rec."Posting No.");
                        until TransInfocodeEntry.Next() = 0;

                    TransIncomeExpenseEntry.SetRange("Store No.", Transaction."Store No.");
                    TransIncomeExpenseEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                    TransIncomeExpenseEntry.SetRange("Transaction No.", Transaction."Transaction No.");
                    if TransIncomeExpenseEntry.FindSet() then
                        repeat
                            PostIncomeExpLine(Rec."Posting No.");
                        until TransIncomeExpenseEntry.Next() = 0;

                    if TransactionStatus."Customer Order ID" <> '' then
                        PostCOAmountToBeRefunded(Rec."Posting No.");

                    if Transaction."Transaction Type" = Transaction."Transaction Type"::NegAdj then begin
                        TransInventoryEntry.SetRange("Store No.", Transaction."Store No.");
                        TransInventoryEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                        TransInventoryEntry.SetRange("Transaction No.", Transaction."Transaction No.");
                        if TransInventoryEntry.FindSet() then
                            repeat
                                PostNegAdjustment(Rec."Posting No.");
                            until TransInventoryEntry.Next() = 0;
                    end;
                end;

                if glUndoItemPosting then
                    TransactionStatus.Status := TransactionStatus.Status::" "
                else
                    TransactionStatus.Status := TransactionStatus.Status::"Items Posted";

                if BackOfficeSetup."Autom. Statistics Update" and (not TransactionStatus."Included in Statistics") then
                    StatisticsUtils.UpdateTransactionStatistics(Transaction, TransactionStatus);
                OnAfterProcessTransactionStatus(TransactionStatus, Statement);
                TransStatusToBuffer(TransactionStatus);

                if not PreviewMode then
                    FindAndMarkStatementNoInPrepaymentInvoiceGLEAndCLE(Transaction."Customer Order ID", Rec."No.");

            until TransactionStatus.Next() = 0;

        LineCounter := 0;
        if not Statement.Debugmode then
            Win.Update(10, Text033);

        StatementLine.Reset();
        StatementLine.SetRange("Statement No.", Rec."No.");
        StatementLine.SetFilter("Tender Type", '<>%1', '');
        if StatementLine.FindSet() then
            repeat
                OnBeforeProcessStatementLine(StatementLine, Statement, GenJnlPostLine, TotalSum, LineCounter, Win, IsHandled);
                if not IsHandled then begin
                    LineCounter := LineCounter + 1;
                    if not Statement.Debugmode then
                        Win.Update(4, LineCounter);
                    TenderType.Get(Store."No.", StatementLine."Tender Type");

                    if StatementLine."Tender Type Card No." = '' then begin
                        if not (TenderType."Function" = TenderType."Function"::Customer) then begin
                            TenderType.TestField("Account No.");
                            TenderType.TestField("Difference G/L Acc.");
                        end;
                        AccType := TenderType."Account Type";
                        if AccType = AccType::"G/L Account" then
                            GLAccountNumber := TenderType."Account No."
                        else
                            BankAccNo := TenderType."Account No.";
                        DiffGLAccountNumber := TenderType."Difference G/L Acc.";

                        if TenderType."Foreign Currency" and (StatementLine."Currency Code" <> '') then
                            if TenderTypeCurrSetup.Get(Store."No.", StatementLine."Tender Type", StatementLine."Currency Code") then begin
                                if TenderTypeCurrSetup."Account No." <> '' then begin
                                    AccType := TenderTypeCurrSetup."Account Type";
                                    if AccType = AccType::"G/L Account" then
                                        GLAccountNumber := TenderTypeCurrSetup."Account No."
                                    else
                                        BankAccNo := TenderTypeCurrSetup."Account No.";
                                end;
                                if TenderTypeCurrSetup."Difference G/L Acc." <> '' then
                                    DiffGLAccountNumber := TenderTypeCurrSetup."Difference G/L Acc.";
                            end;
                    end else begin
                        TenderTypeCardSetup.Get(
                            Store."No.", StatementLine."Tender Type", StatementLine."Tender Type Card No.");
                        if not (TenderType."Function" = TenderType."Function"::Customer) then begin
                            if (TenderTypeCardSetup."Account No." = '') or
                                (TenderTypeCardSetup."Difference G/L Acc." = '')
                            then begin
                                TenderType.TestField("Account No.");
                                TenderType.TestField("Difference G/L Acc.");
                                AccType := TenderType."Account Type";
                                if AccType = AccType::"G/L Account" then
                                    GLAccountNumber := TenderType."Account No."
                                else
                                    BankAccNo := TenderType."Account No.";
                                DiffGLAccountNumber := TenderType."Difference G/L Acc.";
                            end else begin
                                AccType := TenderTypeCardSetup."Account Type";
                                if AccType = AccType::"G/L Account" then
                                    GLAccountNumber := TenderTypeCardSetup."Account No."
                                else
                                    BankAccNo := TenderTypeCardSetup."Account No.";
                                DiffGLAccountNumber := TenderTypeCardSetup."Difference G/L Acc.";
                            end;
                        end;
                    end;

                    if not (TenderType."Function" = TenderType."Function"::Customer) then begin
                        CurrencyGainLoss := 0;
                        IsHandled := false;
                        OnBeforePostTenderTypeStatementLine(TenderType, StatementLine, Store, GLAccountNumber, TotalSum, IsHandled);
                        if not IsHandled then
                            if AccType = AccType::"G/L Account" then begin
                                GLAccount.Get(GLAccountNumber);
                                Description := StrSubstNo('%1 - %2', StatementLine."Tender Type Name", StatementLine.FieldCaption("Counted Amount"));
                                CreateInitialGenJnlLine(Rec, GenJnlLine, GenJournalAccType::"G/L Account", GLAccountNumber, Description, StatementLine."Counted Amount");
                                OnUpdateGnlSafeRefNo(GenJnlLine, SafeStatementLine);
                                if StatementLine."Currency Code" <> '' then begin
                                    GenJnlLine.Validate("Currency Code", StatementLine."Currency Code");
                                    CurrencyGainLoss := CurrencyGainLoss + GenJnlLine."Amount (LCY)" - StatementLine."Counted Amount in LCY";
                                end else
                                    GenJnlLine.Validate("Currency Code", Store."Currency Code");
                                GenJnlLine."VAT Amount" := 0;
                                GenJnlLine."VAT Posting" := GenJnlLine."VAT Posting"::"Manual VAT Entry";
                                GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
                            end else begin
                                BankAcc.Get(BankAccNo);
                                Description := StrSubstNo('%1 - %2', StatementLine."Tender Type Name", StatementLine.FieldCaption("Counted Amount"));
                                CreateInitialGenJnlLine(Rec, GenJnlLine, GenJournalAccType::"Bank Account", BankAccNo, Description, StatementLine."Counted Amount");
                                if StatementLine."Currency Code" <> '' then begin
                                    GenJnlLine.Validate("Currency Code", StatementLine."Currency Code");
                                    CurrencyGainLoss := CurrencyGainLoss + GenJnlLine."Amount (LCY)" - StatementLine."Counted Amount in LCY";
                                end else
                                    GenJnlLine.Validate("Currency Code", Store."Currency Code");
                                GenJnlLine."VAT Amount" := 0;
                                GenJnlLine."VAT Posting" := GenJnlLine."VAT Posting"::"Manual VAT Entry";
                                GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
                            end;
                        GenJnlLine.Validate("VAT Reporting Date", Rec."VAT Reporting Date");

                        IsHandled := false;
                        OnBeforePostCustomerStatementLine(Statement, StatementLine, GenJnlLine, TotalSum, Store, IsHandled);
                        if not IsHandled then
                            if not Store."Paym. Compr. in Statem. Post." then begin
                                CreateGenJnlLineDim(
                                    GenJnlLine,
                                    DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
                                    DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
                                    Database::"LSC Store", Store."No.", 0, '', 0, '', '');
                                if GenJnlLine."Amount (LCY)" <> 0 then begin
                                    AddSourceCurrency(GenJnlLine);
                                    GenJnlPostLine.SetPreviewMode(PreviewMode);
                                    OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
                                    GenJnlPostLine.RunWithCheck(GenJnlLine);
                                end;
                                TotalSum := TotalSum + GenJnlLine."Amount (LCY)";
                            end
                            else
                                UpdatePaymentBuffer(AccType, GenJnlLine."Account No.", StatementLine."Tender Type Name", GenJnlLine."Currency Code", GenJnlLine.Amount, StatementLine."Counted Amount in LCY");

                        if StatementLine."Difference in LCY" <> 0 then begin
                            GLAccount.Get(DiffGLAccountNumber);
                            Description := Text034 + StatementLine."Tender Type";
                            CreateInitialGenJnlLine(Rec, GenJnlLine, GenJournalAccType::"G/L Account", DiffGLAccountNumber, Description, -StatementLine."Difference Amount");
                            if StatementLine."Currency Code" <> '' then begin
                                GenJnlLine.Validate("Currency Code", StatementLine."Currency Code");
                                CurrencyGainLoss := CurrencyGainLoss + GenJnlLine."Amount (LCY)" + StatementLine."Difference in LCY";
                            end else
                                GenJnlLine.Validate("Currency Code", Store."Currency Code");
                            GenJnlLine.Validate("VAT Reporting Date", Rec."VAT Reporting Date");

                            if not Store."Paym. Compr. in Statem. Post." then begin
                                GenJnlLine."Source Code" := BackOfficeSetup."Source Code";

                                CreateGenJnlLineDim(
                                    GenJnlLine,
                                    DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
                                    DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
                                    Database::"LSC Store", Store."No.", 0, '', 0, '', '');
                                if GenJnlLine."Amount (LCY)" <> 0 then begin
                                    AddSourceCurrency(GenJnlLine);
                                    OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
                                    GenJnlPostLine.SetPreviewMode(PreviewMode);
                                    GenJnlPostLine.RunWithCheck(GenJnlLine);
                                end;
                                TotalSum := TotalSum + GenJnlLine."Amount (LCY)";
                            end
                            else
                                UpdatePaymentBuffer(AccType::"G/L Account", GenJnlLine."Account No.", GenJnlLine.Description, GenJnlLine."Currency Code", GenJnlLine.Amount, -StatementLine."Difference in LCY");
                        end;
                        if not Store."Paym. Compr. in Statem. Post." then
                            if CurrencyGainLoss <> 0 then begin
                                Currency.Get(StatementLine."Currency Code");
                                if CurrencyGainLoss > 0 then
                                    GLAccount.Get(Currency."Realized Gains Acc.")
                                else
                                    GLAccount.Get(Currency."Realized Losses Acc.");
                                Description := StrSubstNo(Text054, StatementLine."Tender Type", StatementLine."Currency Code");
                                CreateInitialGenJnlLine(Rec, GenJnlLine, GenJournalAccType::"G/L Account", GLAccount."No.", Description, -CurrencyGainLoss);
                                GenJnlLine.Validate(Amount, -CurrencyGainLoss);
                                GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
                                GenJnlLine.Validate("VAT Reporting Date", Rec."VAT Reporting Date");

                                CreateGenJnlLineDim(
                                    GenJnlLine,
                                    DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
                                    DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
                                    Database::"LSC Store", Store."No.", 0, '', 0, '', '');
                                if GenJnlLine."Amount (LCY)" <> 0 then begin
                                    AddSourceCurrency(GenJnlLine);
                                    OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
                                    GenJnlPostLine.SetPreviewMode(PreviewMode);
                                    GenJnlPostLine.RunWithCheck(GenJnlLine);
                                end;
                                TotalSum := TotalSum + GenJnlLine."Amount (LCY)";
                            end;
                    end;
                end;
                OnAfterProcessTransactionStatus(TransactionStatus, Statement);
            until StatementLine.Next() = 0;

        if Store."Paym. Compr. in Statem. Post." then
            PostPaymentBuffer();

        LineCounter := 0;
        SafeStatementLine.Reset();
        SafeStatementLine.SetRange("Statement No.", Rec."No.");
        SafeStatementLine.SetFilter("Tender Type", '<>%1', '');
        if SafeStatementLine.FindFirst() then
            repeat
                IsHandled := false;
                OnBeforeProcessSafeStatementLine(SafeStatementLine, Statement, GenJnlPostLine, TotalSum, LineCounter, Win, IsHandled);
                if not IsHandled then begin
                    Sign := 1;
                    LineCounter := LineCounter + 1;
                    TenderType.Get(Store."No.", SafeStatementLine."Tender Type");
                    TenderType.TestField("Account No.");
                    TenderType.TestField("Difference G/L Acc.");

                    AccType := TenderType."Account Type";
                    if AccType = AccType::"G/L Account" then
                        GLAccountNumber := TenderType."Account No."
                    else
                        BankAccNo := TenderType."Account No.";
                    DiffGLAccountNumber := TenderType."Difference G/L Acc.";
                    if TenderType."Foreign Currency" and (SafeStatementLine."Currency Code" <> '') then
                        if TenderTypeCurrSetup.Get(Store."No.", SafeStatementLine."Tender Type", SafeStatementLine."Currency Code") then begin
                            if TenderTypeCurrSetup."Account No." <> '' then begin
                                AccType := TenderTypeCurrSetup."Account Type";
                                if AccType = AccType::"G/L Account" then
                                    GLAccountNumber := TenderTypeCurrSetup."Account No."
                                else
                                    BankAccNo := TenderTypeCurrSetup."Account No.";
                            end;
                            if TenderTypeCurrSetup."Difference G/L Acc." <> '' then
                                DiffGLAccountNumber := TenderTypeCurrSetup."Difference G/L Acc.";
                        end;

                    OnAfterSafeStatementAccountSelection(SafeStatementLine, AccType, GLAccountNumber, BankAccNo);

                    if AccType = AccType::"G/L Account" then begin
                        GLAccount.Get(GLAccountNumber);
#pragma warning disable AL0432
                        Description := SafeStatementLine.Description;
#pragma warning restore AL0432
                        CreateInitialGenJnlLine(Rec, GenJnlLine, GenJournalAccType::"G/L Account", GLAccountNumber, Description, Sign * SafeStatementLine.Amount);
                        if SafeStatementLine."Currency Code" <> '' then
                            GenJnlLine.Validate("Currency Code", SafeStatementLine."Currency Code")
                        else
                            GenJnlLine.Validate("Currency Code", Store."Currency Code");
                        GenJnlLine."VAT Amount" := 0;
                        GenJnlLine."VAT Posting" := GenJnlLine."VAT Posting"::"Manual VAT Entry";
                        GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
                        GenJnlLine.Validate("VAT Reporting Date", Rec."VAT Reporting Date");

                        CreateGenJnlLineDim(
                            GenJnlLine,
                            DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
                            DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
                            Database::"LSC Store", Store."No.", 0, '', 0, '', '');

                        if GenJnlLine."Amount (LCY)" <> 0 then begin
                            AddSourceCurrency(GenJnlLine);
                            OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
                            OnBeforeGenJnlLineRunWithCheckPostSafeLine1(GenJnlLine, SafeStatementLine, Rec);
                            GenJnlPostLine.SetPreviewMode(PreviewMode);
                            GenJnlPostLine.RunWithCheck(GenJnlLine);
                        end;
                    end
                    else begin
                        BankAcc.Get(BankAccNo);
#pragma warning disable AL0432
                        Description := SafeStatementLine.Description;
#pragma warning restore AL0432
                        CreateInitialGenJnlLine(Rec, GenJnlLine, GenJournalAccType::"Bank Account", BankAccNo, Description, Sign * SafeStatementLine.Amount);
                        if SafeStatementLine."Currency Code" <> '' then
                            GenJnlLine.Validate("Currency Code", SafeStatementLine."Currency Code")
                        else
                            GenJnlLine.Validate("Currency Code", Store."Currency Code");
                        GenJnlLine."VAT Amount" := 0;
                        GenJnlLine."VAT Posting" := GenJnlLine."VAT Posting"::"Manual VAT Entry";
                        GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
                        GenJnlLine.Validate("VAT Reporting Date", Rec."VAT Reporting Date");

                        CreateGenJnlLineDim(
                            GenJnlLine,
                            DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
                            DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
                            Database::"LSC Store", Store."No.", 0, '', 0, '', '');
                        if GenJnlLine."Amount (LCY)" <> 0 then begin
                            AddSourceCurrency(GenJnlLine);
                            OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
                            OnBeforeGenJnlLineRunWithCheckPostSafeLine2(GenJnlLine, SafeStatementLine, Rec);
                            GenJnlPostLine.SetPreviewMode(PreviewMode);
                            GenJnlPostLine.RunWithCheck(GenJnlLine);
                        end;
                    end;

                    Sign := -1;

                    if SafeStatementLine."Difference in LCY" <> 0 then begin
                        GLAccount.Get(DiffGLAccountNumber);
                        Description := Text034 + SafeStatementLine."Tender Type";
                        CreateInitialGenJnlLine(Rec, GenJnlLine, GenJournalAccType::"G/L Account", DiffGLAccountNumber, Description, Sign * SafeStatementLine."Difference Amount");

                        if SafeStatementLine."Currency Code" <> '' then
                            GenJnlLine.Validate("Currency Code", SafeStatementLine."Currency Code")
                        else
                            GenJnlLine.Validate("Currency Code", Store."Currency Code");
                        GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
                        GenJnlLine.Validate("VAT Reporting Date", Rec."VAT Reporting Date");

                        CreateGenJnlLineDim(
                            GenJnlLine,
                            DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
                            DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
                            Database::"LSC Store", Store."No.", 0, '', 0, '', '');
                        if GenJnlLine."Amount (LCY)" <> 0 then begin
                            AddSourceCurrency(GenJnlLine);
                            OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
                            OnBeforeGenJnlLineRunWithCheckPostSafeLine3(GenJnlLine, SafeStatementLine, Rec);
                            GenJnlPostLine.SetPreviewMode(PreviewMode);
                            GenJnlPostLine.RunWithCheck(GenJnlLine);
                        end;
                        TotalSum := TotalSum + GenJnlLine."Amount (LCY)";
                    end;

                    Sign := -1;

                    Clear(GLAccountNumber);
                    Clear(BankAccNo);

                    if SafeStatementLine."Bal. Account Type" = SafeStatementLine."Bal. Account Type"::"G/L Account" then
                        GLAccountNumber := SafeStatementLine."Bal. Account No."
                    else
                        if SafeStatementLine."Bal. Account Type" = SafeStatementLine."Bal. Account Type"::"Bank Account" then
                            BankAccNo := SafeStatementLine."Bal. Account No.";

                    if GLAccountNumber <> '' then begin
                        GLAccount.Get(GLAccountNumber);
#pragma warning disable AL0432
                        Description := SafeStatementLine.Description;
#pragma warning restore AL0432
                        CreateInitialGenJnlLine(Rec, GenJnlLine, GenJournalAccType::"G/L Account", GLAccountNumber, Description, Sign * SafeStatementLine.Amount);
                        if SafeStatementLine."Currency Code" <> '' then
                            GenJnlLine.Validate("Currency Code", SafeStatementLine."Currency Code")
                        else
                            GenJnlLine.Validate("Currency Code", Store."Currency Code");
                        GenJnlLine."VAT Amount" := 0;
                        GenJnlLine."VAT Posting" := GenJnlLine."VAT Posting"::"Manual VAT Entry";
                        GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
                        GenJnlLine.Validate("VAT Reporting Date", Rec."VAT Reporting Date");

                        CreateGenJnlLineDim(
                            GenJnlLine,
                            DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
                            DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
                            Database::"LSC Store", Store."No.", 0, '', 0, '', '');

                        if GenJnlLine."Amount (LCY)" <> 0 then begin
                            AddSourceCurrency(GenJnlLine);
                            OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
                            OnBeforeGenJnlLineRunWithCheckPostSafeLine4(GenJnlLine, SafeStatementLine, Rec);
                            GenJnlPostLine.SetPreviewMode(PreviewMode);
                            GenJnlPostLine.RunWithCheck(GenJnlLine);
                        end;
                    end
                    else begin
                        BankAcc.Get(BankAccNo);
#pragma warning disable AL0432
                        Description := SafeStatementLine.Description;
#pragma warning restore AL0432
                        CreateInitialGenJnlLine(Rec, GenJnlLine, GenJournalAccType::"Bank Account", BankAccNo, Description, Sign * SafeStatementLine.Amount);
                        if SafeStatementLine."Currency Code" <> '' then
                            GenJnlLine.Validate("Currency Code", SafeStatementLine."Currency Code")
                        else
                            GenJnlLine.Validate("Currency Code", Store."Currency Code");
                        GenJnlLine."VAT Amount" := 0;
                        GenJnlLine."VAT Posting" := GenJnlLine."VAT Posting"::"Manual VAT Entry";
                        GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
                        GenJnlLine.Validate("VAT Reporting Date", Rec."VAT Reporting Date");

                        CreateGenJnlLineDim(
                            GenJnlLine,
                            DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
                            DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
                            Database::"LSC Store", Store."No.", 0, '', 0, '', '');
                        if GenJnlLine."Amount (LCY)" <> 0 then begin
                            AddSourceCurrency(GenJnlLine);
                            OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
                            OnBeforeGenJnlLineRunWithCheckPostSafeLine5(GenJnlLine, SafeStatementLine, Rec);
                            GenJnlPostLine.SetPreviewMode(PreviewMode);
                            GenJnlPostLine.RunWithCheck(GenJnlLine);
                        end;
                    end;

                    Sign := 1;

                    if SafeStatementLine."Difference in LCY" <> 0 then begin
                        GLAccount.Get(TenderType."Bank Diff. G/L Acc.");
                        Description := Text034 + SafeStatementLine."Tender Type";
                        CreateInitialGenJnlLine(Rec, GenJnlLine, GenJournalAccType::"G/L Account", GLAccount."No.", Description, Sign * SafeStatementLine."Difference Amount");
                        if SafeStatementLine."Currency Code" <> '' then
                            GenJnlLine.Validate("Currency Code", SafeStatementLine."Currency Code")
                        else
                            GenJnlLine.Validate("Currency Code", Store."Currency Code");
                        GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
                        GenJnlLine.Validate("VAT Reporting Date", Rec."VAT Reporting Date");

                        CreateGenJnlLineDim(
                            GenJnlLine,
                            DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
                            DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
                            Database::"LSC Store", Store."No.", 0, '', 0, '', '');
                        if GenJnlLine."Amount (LCY)" <> 0 then begin
                            AddSourceCurrency(GenJnlLine);
                            OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
                            OnBeforeGenJnlLineRunWithCheckPostSafeLine6(GenJnlLine, SafeStatementLine, Rec);
                            GenJnlPostLine.SetPreviewMode(PreviewMode);
                            GenJnlPostLine.RunWithCheck(GenJnlLine);
                        end;
                        TotalSum := TotalSum + GenJnlLine."Amount (LCY)";
                    end;
                end;
                OnAfterProcessSafeStatementLine(SafeStatementLine, Statement);
            until SafeStatementLine.Next() = 0;

        OnAfterProcessSafeStatementLines(Statement, GenJnlPostLine, TotalSum);
        LineCounter := 0;
        if not Statement.Debugmode then
            Win.Update(10, Text035);
        PostingBuffer[1].Reset();

        if PostingBuffer[1].FindSet() then
            repeat
                OnBeforeProcessGLedgerPostingBuffer(PostingBuffer[1], Statement, TempDimBufPost);
                LineCounter := LineCounter + 1;
                if PostingBuffer[1]."G/L Account" = '' then
                    Error(
                      Text036,
                      PostingBuffer[1].Type,
                      PostingBuffer[1]."Gen. Business Posting Group",
                      PostingBuffer[1]."Gen. Product Posting Group",
                      PostingBuffer[1].Amount,
                      PostingBuffer[1]."InfoCode Discount Amount",
                      PostingBuffer[1]."Cust. Discount Amount");
                if PostingBuffer[1].Type = PostingBuffer[1].Type::"Bank Account" then begin
                    BankAcc.Get(PostingBuffer[1]."G/L Account");
                    AccountNo := BankAcc."No.";
                    AccountType := GenJournalAccType::"Bank Account";
                end else begin
                    GLAccount.Get(PostingBuffer[1]."G/L Account");
                    AccountNo := GLAccount."No.";
                    AccountType := GenJournalAccType::"G/L Account";
                end;
                if not Statement.Debugmode then
                    Win.Update(5, LineCounter);
                Clear(GenJnlLine);
                GenJnlLine.Init();
                GenJnlLine."Posting Date" := Rec."Posting Date";
                GenJnlLine."Document Date" := Rec."Posting Date";
                GenJnlLine."Document Type" := GenJnlLine."Document Type"::" ";
                GenJnlLine."Document No." := PostingBuffer[1]."Document No.";
                GenJnlLine."External Document No." := Statement."Posting No.";
                GenJnlLine."LSC Customer Order No." := PostingBuffer[1]."Customer Order ID";
                GenJnlLine."LSC Statement No." := Statement."Posting No.";
                GenJnlLine."Account Type" := AccountType;
                GenJnlLine.Validate("Account No.", AccountNo);
                GenJnlLine."Gen. Bus. Posting Group" := PostingBuffer[1]."Gen. Business Posting Group";
                GenJnlLine."Gen. Prod. Posting Group" := PostingBuffer[1]."Gen. Product Posting Group";
                GenJnlLine."VAT Bus. Posting Group" := PostingBuffer[1]."VAT Business Posting Group";
                GenJnlLine."VAT Prod. Posting Group" := PostingBuffer[1]."VAT Product Posting Group";
                GenJnlLine.Validate("VAT Bus. Posting Group");
                GenJnlLine."System-Created Entry" := true;
                if PostingBuffer[1].Type <> PostingBuffer[1].Type::"Bank Account" then
                    if GLAccount."Gen. Posting Type" = GLAccount."Gen. Posting Type"::Purchase then
                        GenJnlLine."Gen. Posting Type" := GenJnlLine."Gen. Posting Type"::Purchase
                    else
                        GenJnlLine."Gen. Posting Type" := GenJnlLine."Gen. Posting Type"::Sale;
                if PostingBuffer[1]."Reverse VAT" then
                    if (PostingBuffer[1]."Payment Posting Description" <> '') then begin
                        GenJnlLine.Description := PostingBuffer[1]."Payment Posting Description";
                        GenJnlLine."Gen. Posting Type" := GenJnlLine."Gen. Posting Type"::" ";
                    end else
                        GenJnlLine.Description := GenJnlLine.Description + ' - ' + VATReverseLabel;
                GenJnlLine.Validate("Currency Code", PostingBuffer[1]."Currency Code");
                CurrencyFactor := GenJnlLine."Currency Factor";
                GenJnlLine.Amount := PostingBuffer[1].Amount;
                GenJnlLine."VAT Amount" := PostingBuffer[1]."VAT Amount";
                GenJnlLine."VAT Base Amount" := PostingBuffer[1]."VAT Base Amount";
                if GenJnlLine."Currency Code" <> '' then begin
                    Currency.Get(GenJnlLine."Currency Code");
                    GenJnlLine.Amount := Round(GenJnlLine.Amount, Currency."Amount Rounding Precision");
                    GenJnlLine."VAT Amount" := Round(GenJnlLine."VAT Amount", Currency."Amount Rounding Precision");
                    GenJnlLine."VAT Base Amount" := Round(GenJnlLine."VAT Base Amount", Currency."Amount Rounding Precision");
                    GenJnlLine."Amount (LCY)" :=
                      Round(CurrencyExchRate.ExchangeAmtFCYToLCY(
                        Rec."Posting Date", GenJnlLine."Currency Code", PostingBuffer[1].Amount, CurrencyFactor));
                    GenJnlLine."VAT Amount (LCY)" :=
                      Round(CurrencyExchRate.ExchangeAmtFCYToLCY(
                        Rec."Posting Date", GenJnlLine."Currency Code", PostingBuffer[1]."VAT Amount", CurrencyFactor));
                    GenJnlLine."VAT Base Amount (LCY)" :=
                      Round(CurrencyExchRate.ExchangeAmtFCYToLCY(
                        Rec."Posting Date", GenJnlLine."Currency Code", PostingBuffer[1]."VAT Base Amount", CurrencyFactor));
                end else begin
                    GenJnlLine.Amount := Round(GenJnlLine.Amount, GenLedgerSetup."Amount Rounding Precision");
                    GenJnlLine."VAT Amount" := Round(GenJnlLine."VAT Amount", GenLedgerSetup."Amount Rounding Precision");
                    GenJnlLine."VAT Base Amount" := Round(GenJnlLine."VAT Base Amount", GenLedgerSetup."Amount Rounding Precision");
                end;

                GenJnlLine."VAT Posting" := GenJnlLine."VAT Posting"::"Manual VAT Entry";
                GenJnlLine."Shortcut Dimension 1 Code" := PostingBuffer[1]."Department Code";
                GenJnlLine."Shortcut Dimension 2 Code" := PostingBuffer[1]."Project Code";
                GenJnlLine."Source Code" := BackOfficeSetup."Source Code";

                if PostingBuffer[1]."Customer No." <> '' then begin
                    CustomerRec.Get(PostingBuffer[1]."Customer No.");
                    GenJnlLine."Sell-to/Buy-from No." := PostingBuffer[1]."Customer No.";
                    GenJnlLine."Bill-to/Pay-to No." := PostingBuffer[1]."Customer No.";
                    GenJnlLine."Country/Region Code" := CustomerRec."Country/Region Code";
                    GenJnlLine."VAT Registration No." := CustomerRec."VAT Registration No.";
                    GenJnlLine."Source Type" := GenJnlLine."Source Type"::Customer;
                    GenJnlLine."Source No." := PostingBuffer[1]."Customer No.";
                end;

                if PostingBuffer[1].isDiscount then begin
                    GenJnlLine."Gen. Posting Type" := Enum::"General Posting Type"::" ";
                    GenJnlLine."EU 3-Party Trade" := false;
                    GenJnlLine."VAT Calculation Type" := GenJnlLine."VAT Calculation Type"::"Normal VAT";
                    GenJnlLine."Bill-to/Pay-to No." := '';
                end;
                GenJnlLine.Validate("VAT Reporting Date", Rec."VAT Reporting Date");

                OnProcessGLedgerPostingBufferAfterInitGenJnlLine(Rec, GenJnlLine, PostingBuffer[1]);

                TempDimBufNew.DeleteAll();
                TempDimSetEntry.DeleteAll();
                if GetDimensions(PostingBuffer[1]."Entry No.", TempDimBufNew) then begin
                    if TempDimBufNew.FindSet() then
                        repeat
                            DimVal.Get(TempDimBufNew."Dimension Code", TempDimBufNew."Dimension Value Code");
                            TempDimSetEntry."Dimension Code" := TempDimBufNew."Dimension Code";
                            TempDimSetEntry."Dimension Value Code" := TempDimBufNew."Dimension Value Code";
                            TempDimSetEntry."Dimension Value ID" := DimVal."Dimension Value ID";
                            TempDimSetEntry.Insert();
                        until TempDimBufNew.Next() = 0;
                    GenJnlLine."Dimension Set ID" := DimMgt.GetDimensionSetID(TempDimSetEntry);
                end;

                OnBeforeProcessLedgerPostingBuffer(GenJnlLine, PostingBuffer[1], Statement);

                GenJnlPostLine.SetPreviewMode(PreviewMode);
                GenJnlPostLine.RunWithCheck(GenJnlLine);
                TotalSum := TotalSum + GenJnlLine."Amount (LCY)" + GenJnlLine."VAT Amount (LCY)";
                OnAfterProcessLedgerPostingBuffer(PostingBuffer[1], Statement);
            until PostingBuffer[1].Next() = 0;

        PostingBuffer[1].DeleteAll();

        OnAfterDeletePostingBufferV2(Rec, GenJnlLine, TempDimBufNew, TotalSum, Win, GenJnlPostLine);

        if not Statement.Debugmode then
            Win.Update(10, Text037);

        OnBeforeCalculateRoundingDifference(Statement, GenJnlLine, TotalSum);

        if TotalSum <> 0 then begin
            Store.TestField("Rounding Account");
            if Store."Max. Round. in Stmt." <> 0 then
                if Store."Max. Round. in Stmt." < Abs(TotalSum) then
                    Error(
                      Text038,
                      TotalSum, Store.FieldCaption("Max. Round. in Stmt."),
                      Store."Max. Round. in Stmt.", Store.TableCaption, Store."No.");
            GLAccount.Get(Store."Rounding Account");
            Clear(GenJnlLine);
            GenJnlLine.Init();
            GenJnlLine."Posting Date" := Rec."Posting Date";
            GenJnlLine."Document Date" := Rec."Posting Date";
            GenJnlLine."Document Type" := GenJnlLine."Document Type"::" ";
            GenJnlLine."Document No." := Rec."Posting No.";
            GenJnlLine."LSC Statement No." := Statement."Posting No.";
            GenJnlLine."External Document No." := Statement."Posting No.";
            GenJnlLine.Validate("Account No.", GLAccount."No.");
            GenJnlLine.Description := GLAccount.Name;
            if GenJnlLine."VAT %" <> 0 then begin
                GenJnlLine."VAT Posting" := GenJnlLine."VAT Posting"::"Manual VAT Entry";
                GenJnlLine."VAT Amount" := -TotalSum * (1 - (1 / (1 + (GenJnlLine."VAT %" / 100))));
                GenJnlLine.Amount := -TotalSum - GenJnlLine."VAT Amount";
                GenJnlLine."VAT Base Amount" := GenJnlLine.Amount;
                GenJnlLine.Amount := Round(GenJnlLine.Amount, GenLedgerSetup."Amount Rounding Precision");
                GenJnlLine."VAT Amount" := Round(GenJnlLine."VAT Amount", GenLedgerSetup."Amount Rounding Precision");
                GenJnlLine."VAT Base Amount" := Round(GenJnlLine."VAT Base Amount", GenLedgerSetup."Amount Rounding Precision");
            end else
                GenJnlLine.Validate(Amount, -TotalSum);
            GenJnlLine."System-Created Entry" := true;
            GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
            GenJnlLine.Validate("VAT Reporting Date", Rec."VAT Reporting Date");

            CreateGenJnlLineDim(
              GenJnlLine,
              DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
              DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
              Database::"LSC Store", Store."No.", 0, '', 0, '', '');
            AddSourceCurrency(GenJnlLine);
            OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
            GenJnlPostLine.SetPreviewMode(PreviewMode);
            GenJnlPostLine.RunWithCheck(GenJnlLine);
        end;

        LineCounter := 0;
        if not Statement.Debugmode then
            Win.Update(10, Text050);
        if BOMItemBuffer.FindSet() then begin
            BOMItemBuffer2.DeleteAll();
            repeat
                LineCounter := LineCounter + 1;
                if not Statement.Debugmode then
                    Win.Update(6, LineCounter);
                BOMCalcStdCost(BOMItemBuffer."Item No.", BOMItemBuffer.Date);
            until BOMItemBuffer.Next() = 0;
        end;
        LineCounter := 0;
        if not Statement.Debugmode then
            Win.Update(10, Text051);
        BOMLineNo := 0;
        if BOMPostingBuffer[1].FindSet() then
            repeat
                IsHandled := false;
                LineCounter := LineCounter + 1;
                if not Statement.Debugmode then
                    Win.Update(6, LineCounter);
                OnBeforePostBOMOnRun(BOMPostingBuffer[1], Statement."Posting No.", IsHandled);
                if not IsHandled then
                    PostBOM();
                Clear(GenJnlPostLine);
            until BOMPostingBuffer[1].Next() = 0;
        LineCounter := 0;
        if not Statement.Debugmode then
            Win.Update(10, Text060);
        ItemAdjustPostBuffer[1].Reset();
        if ItemAdjustPostBuffer[1].FindSet() then
            repeat
                LineCounter := LineCounter + 1;
                if not Statement.Debugmode then
                    Win.Update(6, LineCounter);
                PostItemAdjustment();
            until ItemAdjustPostBuffer[1].Next() = 0;
        TransPostingFunctions.InsertInvAdjustEntryV2(ItemAdjustPostBuffer[1]);
        LineCounter := 0;
        if not Statement.Debugmode then
            Win.Update(10, Text039);
        ItemPostingBuffer[1].Reset();
        ItemPostingBuffer[1].SetCurrentKey("Item No.", "Location Code", "Department Code", "Source No.", "Serial No.", "Lot No.", Date, "Salesperson Code", "Neg. Qty", "Offer No.", "Promotion No.", "Entry No.");
        ItemPostingBuffer[1].SetRange(Type, ItemPostingBuffer[1].Type::Sales);
        ItemPostingBuffer[1].SetAscending("Neg. Qty", false);
        if ItemPostingBuffer[1].FindSet() then
            repeat
                OnBeforeProcessItemPostingBufferV2(ItemPostingBuffer[1], Statement);
                LineCounter := LineCounter + 1;
                if not Statement.Debugmode then
                    Win.Update(6, LineCounter);
                if (ItemPostingBuffer[1]."Serial No." <> '') or (ItemPostingBuffer[1]."Lot No." <> '') then begin
                    CompressItemPostingBuffer();
                    if OkToPostDirect(ItemPostingBuffer[1]) then
                        PostItem
                    else
                        if FindReversePosting(ItemPostingBuffer[1], ItemPostingBuffer_RV) then begin
                            ItemPostingBuffer_Temp := ItemPostingBuffer[1];
                            ItemPostingBuffer[1] := ItemPostingBuffer_RV;
                            PostItem();
                            ItemPostingBuffer[1] := ItemPostingBuffer_Temp;
                            PostItem();
                        end else
                            PostItem();
                    ItemPostingBuffer[1].Delete();
                end else
                    PostItem();
                OnAfterProcessItemPostingBufferV2(ItemPostingBuffer[1], Statement);
            until ItemPostingBuffer[1].Next() = 0;

        LineCounter := 0;
        if not Statement.Debugmode then
            Win.Update(10, Text046);
        ItemPostingBuffer[1].Reset();
        ItemPostingBuffer[1].SetRange(Type, ItemPostingBuffer[1].Type::NegAdjust);
        if ItemPostingBuffer[1].FindSet() then
            repeat
                OnBeforeProcessItemPostingBufferV2(ItemPostingBuffer[1], Statement);
                LineCounter := LineCounter + 1;
                if not Statement.Debugmode then
                    Win.Update(6, LineCounter);
                if ItemPostingBuffer[1].Quantity <> 0 then begin
                    GetItem(ItemPostingBuffer[1]."Item No.", ItemPostingBuffer[1], Item);
                    TransPostingFunctions.SetItemBlockReserve(Item."No.");
                    Clear(ItemJnlLine);
                    ItemJnlLine.Init();
                    ItemJnlLine."Item No." := ItemPostingBuffer[1]."Item No.";
                    ItemJnlLine."Variant Code" := ItemPostingBuffer[1]."Source No.";
                    ItemJnlLine."Posting Date" := ItemPostingBuffer[1].Date;
                    ItemJnlLine."Document Date" := Rec."Posting Date";
                    if Item.Type = Item.Type::Inventory then
                        ItemJnlLine.Validate("Entry Type", ItemJnlLine."Entry Type"::"Negative Adjmt.")
                    else
                        ItemJnlLine."Entry Type" := ItemJnlLine."Entry Type"::"Negative Adjmt.";
                    ItemJnlLine."Document No." := ItemPostingBuffer[1]."Document No.";
                    ItemJnlLine."LSC BO Doc. No." := Statement."Posting No.";
                    ItemJnlLine.Description := Item.Description;
                    ItemJnlLine."Location Code" := ItemPostingBuffer[1]."Location Code";
                    ItemJnlLine."Inventory Posting Group" := Item."Inventory Posting Group";
                    ItemJnlLine."Source Posting Group" := '';
                    if Item."Base Unit of Measure" <> '' then begin
                        ItemJnlLine.Validate("Unit of Measure Code", Item."Base Unit of Measure");
                        ItemJnlLine.Validate(Quantity, ItemPostingBuffer[1].Quantity);
                    end else begin
                        ItemJnlLine."Unit of Measure Code" := '';
                        ItemJnlLine."Qty. per Unit of Measure" := 1;
                        ItemJnlLine.Validate("Quantity (Base)", ItemPostingBuffer[1].Quantity);
                    end;
                    ItemJnlLine."Source Code" := BackOfficeSetup."Source Code";
                    ItemJnlLine."Gen. Bus. Posting Group" := ItemPostingBuffer[1]."Gen. Bus. Posting Group";
                    ItemJnlLine."Gen. Prod. Posting Group" := ItemPostingBuffer[1]."Gen. Prod. Posting Group";
                    ItemJnlLine."LSC Offer No." := ItemPostingBuffer[1]."Offer No.";
                    ItemJnlLine."LSC Promotion No." := ItemPostingBuffer[1]."Promotion No.";

                    ItemJnlLine."Expiration Date" := ItemPostingBuffer[1]."Expiration Date";
                    if (ItemPostingBuffer[1]."Serial No." <> '') or (ItemPostingBuffer[1]."Lot No." <> '') then
                        TransPostingFunctions.AddSerialNoAndLotNoTracking(ItemJnlLine, ItemPostingBuffer[1]."Serial No.", ItemPostingBuffer[1]."Lot No.", ItemPostingBuffer[1]."Expiration Date");

                    CodeDictionary_l.Add(Database::Item, ItemJnlLine."Item No.");
                    AddToDimList(CodeDictionary_l, DimSource_l);
                    CodeDictionary_l.Add(Database::"LSC Store", Store."No.");
                    AddToDimList(CodeDictionary_l, DimSource_l);

                    CreateItemJnlLineDim(ItemJnlLine, DimSource_l, ItemPostingBuffer[1]."Sales Type");
                    OnBeforeItemJnlLinePostLineV2(ItemJnlLine, Statement, ItemPostingBuffer[1]);
                    if not PreviewMode then
                        ItemJnlPostLine.RunWithCheck(ItemJnlLine);
                    OnAfterItemJnlLinePostLine(ItemJnlLine, Statement);
                    TransPostingFunctions.ResetItemBlockReserve();
                end;
                OnAfterProcessItemPostingBufferV2(ItemPostingBuffer[1], Statement);
            until ItemPostingBuffer[1].Next() = 0;

        ItemPostingBuffer[1].SetRange(Type);
        ItemPostingBuffer[1].DeleteAll();

        if not Statement.Debugmode then
            Win.Update(10, Text040);

        TransSalesEntry.Reset();
        TransPmtEntry.Reset();
        TransIncomeExpenseEntry.Reset();
        TransInventoryEntry.Reset();
        LineCounter := 0;

        GetTransStatusBuffer(TransactionStatusTmp);
        if TransactionStatusTmp.FindSet() then
            repeat
                OnBeforeEndProcessTransactionStatus(TransactionStatusTmp, Statement);
                LineCounter := LineCounter + 1;
                if not Statement.Debugmode then
                    Win.Update(7, LineCounter);
                TransactionStatusTmp.Status := TransactionStatus.Status::Posted;
                TransactionStatusTmp."Posted Statement No." := Rec."Posting No.";
                OnBeforeEndProcessTransactionStatus(TransactionStatusTmp, Statement);
                TransStatusToBuffer(TransactionStatusTmp);
            until TransactionStatusTmp.Next() = 0;

        if Rec."Closing Method" = Rec."Closing Method"::Shift then begin
            WorkShift.Get(Rec."Store No.", Rec."Shift Date", Rec."Shift No.");
            WorkShift.Status := WorkShift.Status::Posted;
            WorkShift.Modify();
            WorkShiftEntry.SetRange("Store No.", WorkShift."Store No.");
            WorkShiftEntry.SetRange("Shift Date", WorkShift."Shift Date");
            WorkShiftEntry.SetRange("Shift No.", WorkShift."Shift No.");
            if WorkShiftEntry.FindSet() then
                repeat
                    WorkShiftEntry.Status := WorkShiftEntry.Status::Posted;
                    WorkShiftEntry."Closing Date" := Today;
                    WorkShiftEntry."Closing Time" := Time;
                    WorkShiftEntry.Modify();
                until WorkShiftEntry.Next() = 0;
        end;

        Rec."Posted Date" := Today;
        Rec."Posted Time" := Time;
        Rec.Modify();

        SafePost.PostStatement(Rec);
        OnAfterPostStatement(Rec);

        PostedStatement.Init();
        PostedStatement.TransferFields(Rec);
        PostedStatement."No." := Rec."Posting No.";
        PostedStatement."No. Series." := Rec."Posting Nos.";
        PostedStatement."Pre-Assign. No. Series" := Rec."No. Series.";
        PostedStatement."Pre-Assigned No." := Rec."No.";

        Rec.CalcFields(
          "Items/Barc. Not on File", "Trans. on Wrong Shift", "Sales Amount",
          "VAT Amount", "Total Discount", "Line Discount", Income, Expenses, "Discount Total Amount",
          "No. of Blocked Items", "No. of Blocked Cust.", "Trans. w/ Sale/Pmt. Diff.");
        PostedStatement."Items/Barc. Not on File" := Rec."Items/Barc. Not on File";
        PostedStatement."Trans. on Wrong Shift" := Rec."Trans. on Wrong Shift";
        PostedStatement."Sales Amount" := Rec."Sales Amount";
        PostedStatement."VAT Amount" := Rec."VAT Amount";
        PostedStatement."Total Discount" := Rec."Total Discount";
        PostedStatement."Line Discount" := Rec."Line Discount";
        PostedStatement."Discount Total Amount" := Rec."Discount Total Amount";
        PostedStatement.Income := Rec.Income;
        PostedStatement.Expenses := Rec.Expenses;
        PostedStatement."No. of Blocked Items" := Rec."No. of Blocked Items";
        PostedStatement."No. of Blocked Cust." := Rec."No. of Blocked Cust.";
        PostedStatement."Trans. w/ Sale/Pmt. Diff." := Rec."Trans. w/ Sale/Pmt. Diff.";

        PostedStatement.Insert(true);

        StatementLine.SetRange("Statement No.", Statement."No.");
        if StatementLine.FindSet() then
            repeat
                PostedStatementLine.Init();
                PostedStatementLine.TransferFields(StatementLine);
                PostedStatementLine."Statement No." := Rec."Posting No.";
                OnBeforeInsertPostedStatementLine(StatementLine, PostedStatementLine);
                PostedStatementLine.Insert(true);
            until StatementLine.Next() = 0;
        Clear(StatementLine);
        StatementLine.SetRange("Statement No.", Statement."No.");
        StatementLine.DeleteAll();

        SafeStatementLine.SetRange("Statement No.", Statement."No.");
        if SafeStatementLine.FindSet() then
            repeat
                PostedSafeStatementLine.Init();
                // Transferfields temporarily replaced by the TranferfieldsFromSafeStatementLine function while the "Bal. Account Name" field in the "LSC Posted Safe Statement Line" table is not removed.
                // PostedSafeStatementLine.TransferFields(SafeStatementLine);
                TranferfieldsFromSafeStatementLine(PostedSafeStatementLine, SafeStatementLine);
                PostedSafeStatementLine."Statement No." := Rec."Posting No.";

                OnBeforeInsertPostedSafeStatementLine(PostedSafeStatementLine, SafeStatementLine, Statement, PostedStatement);
                PostedSafeStatementLine.Insert(true);
            until SafeStatementLine.Next() = 0;
        Clear(SafeStatementLine);
        SafeStatementLine.SetRange("Statement No.", Statement."No.");
        SafeStatementLine.DeleteAll();

        CashDeclaration.SetRange("Statement No.", Rec."No.");
        if CashDeclaration.FindSet() then
            repeat
                PostedCashDeclaration.Init();
                PostedCashDeclaration.TransferFields(CashDeclaration);
                PostedCashDeclaration."Statement No." := Rec."Posting No.";
                PostedCashDeclaration.Insert();
            until CashDeclaration.Next() = 0;
        CashDeclaration.DeleteAll();

        FlushTablesBuffers();

        if not Statement.Debugmode then
            Win.Close();

        if PreviewMode then
            GenJnlPostPreview.ThrowError();

        OnBeforeDeleteStatement(Rec);

        Clear(Statement);
        Statement := Rec;
        Statement.Delete();
        TransPostingFunctions.CloseFunction();

        UpdateAnalysisView.UpdateAll(0, true);

        if SchedulerSetup."Statment Post Repl. Job" <> '' then begin
            SchedulerJob.Get(SchedulerSetup."Statment Post Repl. Job");
            SchedulerJob.SetLogEntryNo(0);
            SchedulerJob.SetLocationCode('');
            SchedulerUtil.RunScheduleJob(SchedulerJob, true);
            SchedulerJob.Modify();
        end;

        /* //!!!
        if not PreviewMode then
            if not RunningFromBatchPosting then
                ShowPostedConfirmationMessage(Rec);
        */

        BOUtils.ReplicateUsingRegEntry();

        OnAfterStatementPostBeforeCommit(Rec);

        if (BOUtils.IsReplenishmentPermitted()) and
          (ReplenSetup.Get()) then begin
            if not PreviewMode then
                Commit();
            ReplenishmUpdLikeForLike.UpdateLikeForLikeFromStmt(PostedStatement."No.");
        end;

        if BackOfficeSetup."Commission Active" and BackOfficeSetup."Calculate in Statem.Posting" then begin
            CommissionUtils.SetRunFromPosting(true);
            CommissionUtils.StatementPosting(PostedStatement."No.");
        end;

        if ShowReturnOrderMsg then
            if FirstReturnOrderNo = LastReturnOrderNo then
                Message(Text055, FirstReturnOrderNo)
            else
                Message(Text056, FirstReturnOrderNo, LastReturnOrderNo);

        OnAfterStatementPost(Rec);
    end;

    var
        Store: Record "LSC Store";
        BackOfficeSetup: Record "LSC Retail Setup";
        SchedulerSetup: Record "LSC Scheduler Setup";
        SalesReceivablesSetup: Record "Sales & Receivables Setup";
        Statement: Record "LSC Statement";
        StatementLine: Record "LSC Statement Line";
        PostedStatement: Record "LSC Posted Statement";
        PostedStatementLine: Record "LSC Posted Statement Line";
        Transaction: Record "LSC Transaction Header";
        TransSalesEntry: Record "LSC Trans. Sales Entry";
        TransPmtEntry: Record "LSC Trans. Payment Entry";
        TransIncomeExpenseEntry: Record "LSC Trans. Inc./Exp. Entry";
        TransInfocodeEntry: Record "LSC Trans. Infocode Entry";
        TenderType: Record "LSC Tender Type";
        TenderTypeCardSetup: Record "LSC Tender Type Card Setup";
        CustomerRec: Record Customer;
        GenJnlLine: Record "Gen. Journal Line";
        ItemJnlLine: Record "Item Journal Line";
        Item: Record Item;
        IncomeExpenseAcc: Record "LSC Income/Expense Account";
        GenPostingSetup: Record "General Posting Setup";
        TransIncomeExpenseEntryBuffer: Record "LSC Trans. Inc./Exp. Entry" temporary;
        GLAccount: Record "G/L Account";
        GLAccount2: Record "G/L Account";
        BankAcc: Record "Bank Account";
        WorkShift: Record "LSC Work Shift RBO";
        WorkShiftEntry: Record "LSC Work Shift Entry";
        VATPostingSetup: Record "VAT Posting Setup";
        OldCustLedgEntry: Record "Cust. Ledger Entry";
        CurrencyExchRate: Record "Currency Exchange Rate";
        Currency: Record Currency;
        GenLedgerSetup: Record "General Ledger Setup";
        CashDeclaration: Record "LSC Cash Declaration";
        RetailBOMJnlLine: Record "LSC Retail BOM Journal Line";
        TransInventoryEntry: Record "LSC Trans. Inventory Entry";
        SchedulerJob: Record "LSC Scheduler Job Header";
        TransactionStatus: Record "LSC Transaction Status";
        TransSalesEntryStatus: Record "LSC Trans. Sales Entry Status";
        SalesTypes: Record "LSC Sales Type";
        SafeStatementLine: Record "LSC Safe Statement Line";
        PostedSafeStatementLine: Record "LSC Posted Safe Statement Line";
        TenderTypeCurrSetup: Record "LSC Tender Type Currency Setup";
        SourceCode: Record "Source Code";
        PostingBuffer: array[2] of Record "LSC Ledger Posting Buffer" temporary;
        PaymPostingBuffer: Record "LSC Ledger Posting Buffer" temporary;
        ItemPostingBuffer: array[2] of Record "LSC Item Posting Buffer V2" temporary;
        ItemBuffer: Record "LSC Item Posting Buffer V2" temporary;
        TempDimBufNew: Record "Dimension Buffer" temporary;
        TempDimBufPost: Record "Dimension Buffer" temporary;
        TempDimSetEntry: Record "Dimension Set Entry" temporary;
        BOMPostingBuffer: array[2] of Record "LSC BOM Posting Buffer" temporary;
        TmpInteger: Record "Integer" temporary;
        TransactionStatusTmp: Record "LSC Transaction Status" temporary;
        BOMItemBuffer: Record "LSC BOM Posting Buffer" temporary;
        BOMItemBuffer2: Record "LSC BOM Posting Buffer" temporary;
        ItemAdjustPostBuffer: array[2] of Record "LSC Item Posting Buffer V2" temporary;
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
        ItemJnlPostLine: Codeunit "Item Jnl.-Post Line";
        DimManagement: Codeunit DimensionManagement;
        DimMgt: Codeunit DimensionManagement;
        RetailBOMJnlPostLine: Codeunit "LSC Retail BOM Jnl.-Post Line";
        DiscLedgerMgt: Codeunit "LSC Discount Ledger Mgt.";
        NoSeries: Codeunit "No. Series";
        PostingExceptionUtility: Codeunit "LSC Posting Exception Utility";
        TransPostingFunctions: Codeunit "LSC Trans. Posting Functions";
        BufferUtility: Codeunit "LSC Buffer Utility";
        BOUtils: Codeunit "LSC BO Utils";
        COPrepaymentInvoiceMan: Codeunit "BMG CO Prepayment Invoice Mgt";
        Win: Dialog;
        GLAccountNumber: Code[20];
        BankAccNo: Code[20];
        DiffGLAccountNumber: Code[20];
        GLSetupShortcutDimCode: array[8] of Code[20];
        No: array[10] of Code[20];
        FirstReturnOrderNo: Code[20];
        LastReturnOrderNo: Code[20];
        Txt: Text[250];
        DocType: Enum "Gen. Journal Document Type";
        AccType: Enum "LSC Tender Posting Acc. Type";
        GenJournalAccType: Enum "Gen. Journal Account Type";
        TotalSum: Decimal;
        CurrencyFactor: Decimal;
        AmountToPost: Decimal;
        IncExpVATPercent: Decimal;
        LineCounter: Integer;
        TableID: array[10] of Integer;
        HasGotGLSetup: Boolean;
        CompletePost: Boolean;
        ShowReturnOrderMsg: Boolean;
        RunningFromBatchPosting: Boolean;
        glUndoItemPosting: Boolean;
        SkipCLEPosting: Boolean;
        PreviewMode: Boolean;
        Text054: Label 'Tender Type %1, currency %2 gains/losses';
        Text002: Label 'Posting was cancelled.';
        Text014: Label 'No Statement Lines found.';
        Text031: Label '%1 %2 does not exist in %3.';
        StatementRecalculationWarningTxt: Label 'Settings controlling how the Statement is calculated have been changed. Please clear and recalculate the Statement before continuing.';
        UnresolvedSerialNumbersMessageErr: Label 'There are %1 unresolved serial numbers attached to this statement. They must be resolved before the statement can be posted.';
        BatchPostingQueueStatusMessage: Label 'Statement has already been posted to the Batch Posting Queue.';
        PostStatementQst: Label 'Do you want to post the Statement?';

    internal procedure PostItemSales(var TransDiscEntryTemp: Record "LSC Trans. Discount Entry" temporary; DocNumber: Code[20]; PostGLEntries: Boolean)
    var
        Staff: Record "LSC Staff";
        SalesType2: Record "LSC Sales Type";
        PostingException: Record "LSC Posting Exception";
        GlobalDimension1Code: Code[20];
        GlobalDimension2Code: Code[20];
        LocCode: Code[10];
        SalesTypeCode: Code[20];
        GenBusPostingGroup: Code[20];
        GenProdPostingGroup: Code[20];
        VATBusPostingGroup: Code[20];
        VATProdPostingGroup: Code[20];
        VATFactor: Decimal;
        CustDiscountAmount: Decimal;
        CustDiscountVATAmount: Decimal;
        POSInvDiscAmount: Decimal;
        POSInvDiscVATAmount: Decimal;
        InfoCodeDiscountAmount: Decimal;
        InfoCodeDiscVATAmount: Decimal;
        POSLineDiscAmount: Decimal;
        POSLineDiscVATAmount: Decimal;
        PeriodicDiscAmount: Decimal;
        PeriodicDiscVATAmount: Decimal;
        CouponDiscAmount: Decimal;
        CouponDiscVATAmount: Decimal;
        POSLineDiscOfferAmount: Decimal;
        POSLineDiscOfferVATAmount: Decimal;
        POSTotalDiscOfferAmount: Decimal;
        POSTotalDiscOfferVATAmount: Decimal;
        POSTenderDiscOfferAmount: Decimal;
        POSTenderDiscOfferVATAmount: Decimal;
        TmpDiscAmt: Decimal;
        GLEntryNo, ItemEntryNo : Integer;
        Len: Integer;
        OfferType: Enum "LSC Trans. Disc. Ent Offer Typ";
        IsHandled: Boolean;
        FuelItem: Boolean;
    begin
        OnBeforePostItemSale(TransSalesEntry, Transaction, Statement, DocNumber, PostGLEntries, IsHandled);
        if IsHandled then
            exit;

        GetItem(TransSalesEntry."Item No.", TransSalesEntry, Item);
        //!!!FuelItem := BOUtils.CheckFuelItem(Item);

        GenBusPostingGroup := TransSalesEntry."Gen. Bus. Posting Group";
        if GenBusPostingGroup = '' then
            if Transaction."To Account" then
                GenBusPostingGroup := CustomerRec."Gen. Bus. Posting Group"
            else
                GenBusPostingGroup := Store."Gen. Bus. Post. Gr.";

        GenProdPostingGroup := TransSalesEntry."Gen. Prod. Posting Group";
        if GenProdPostingGroup = '' then
            GenProdPostingGroup := Item."Gen. Prod. Posting Group";

        GenPostingSetup.get(GenBusPostingGroup, GenProdPostingGroup);

        VATBusPostingGroup := TransSalesEntry."VAT Bus. Posting Group";
        if VATBusPostingGroup = '' then
            VATBusPostingGroup := Transaction."VAT Bus.Posting Group";
        VATProdPostingGroup := TransSalesEntry."VAT Prod. Posting Group";
        if VATProdPostingGroup = '' then
            VATProdPostingGroup := Item."VAT Prod. Posting Group";
        VATPostingSetup.get(VATBusPostingGroup, VATProdPostingGroup);

        OnAfterGetVATPostingSetup(VATPostingSetup, Transaction, TransSalesEntry, GenPostingSetup);

        VATFactor := (1 + (VATPostingSetup."VAT %" / 100));
        if VATPostingSetup."VAT Calculation Type" <> VATPostingSetup."VAT Calculation Type"::"Normal VAT" then
            VATFactor := 1;

        Clear(TableID);
        Clear(No);

        TableID[1] := Database::Item;
        No[1] := Item."No.";
        TableID[2] := Database::"LSC Store";
        No[2] := Store."No.";
        TableID[3] := Database::"G/L Account";

        if Transaction."Sale Is Return Sale" then
            No[3] := GenPostingSetup."Sales Credit Memo Account"
        else
            No[3] := GenPostingSetup."Sales Account";

        Len := 3;
        if Transaction."Customer No." <> '' then begin
            TableID[4] := Database::Customer;
            No[4] := Transaction."Customer No.";
            Len := 4;
        end;

        SalesTypeCode := Transaction."Sales Type";
        if TransSalesEntry."Sales Type" <> '' then
            SalesTypeCode := TransSalesEntry."Sales Type";

        if SalesTypeCode <> '' then begin
            Len := Len + 1;
            TableID[Len] := Database::"LSC Sales Type";
            No[Len] := SalesTypeCode;
        end;

        GetDefaultDim(
            TableID, No, BackOfficeSetup."Source Code", GlobalDimension1Code,
            GlobalDimension2Code, Len);
        OnAfterGetDefaultDimInPostItemSales(SalesTypeCode, GlobalDimension1Code, GlobalDimension2Code, TempDimBufNew, Transaction, TransSalesEntry);

        GLEntryNo := FindDimensions(TempDimBufNew);
        if GLEntryNo = 0 then
            GLEntryNo := InsertDimensions(TempDimBufNew);

        if PostGLEntries then begin
            Clear(PostingBuffer[1]);
            PostingBuffer[1].Type := PostingBuffer[1].Type::Item;
            GenPostingSetup.TestField("Sales Account");
            if Transaction."To Account" then
                PostingBuffer[1]."Customer No." := CustomerRec."No.";
            PostingBuffer[1]."Entry No." := GLEntryNo;

            if Transaction."Sale Is Return Sale" then begin
                GenPostingSetup.TestField("Sales Credit Memo Account");
                PostingBuffer[1]."G/L Account" := GenPostingSetup."Sales Credit Memo Account";
            end
            else
                PostingBuffer[1]."G/L Account" := GenPostingSetup."Sales Account";

            PostingBuffer[1]."Gen. Business Posting Group" := GenPostingSetup."Gen. Bus. Posting Group";
            PostingBuffer[1]."Gen. Product Posting Group" := GenPostingSetup."Gen. Prod. Posting Group";
            PostingBuffer[1]."VAT Business Posting Group" := VATPostingSetup."VAT Bus. Posting Group";
            PostingBuffer[1]."VAT Product Posting Group" := VATPostingSetup."VAT Prod. Posting Group";
            PostingBuffer[1]."VAT Calculation Type" := PostingBuffer[1]."VAT Calculation Type"::"Normal VAT";
            PostingBuffer[1]."Department Code" := GlobalDimension1Code;
            PostingBuffer[1]."Project Code" := GlobalDimension2Code;
            PostingBuffer[1]."Currency Code" := Transaction."Trans. Currency";
            PostingBuffer[1]."Document No." := DocNumber;
            PostingBuffer[1].Amount := TransSalesEntry."Net Amount";
            PostingBuffer[1]."VAT Base Amount" := TransSalesEntry."Net Amount";
            PostingBuffer[1]."VAT Amount" := TransSalesEntry."VAT Amount";

            OnAfterInitLedgerPostingBufferPostItemSales(PostingBuffer[1], TransSalesEntry, Transaction);

            Clear(CustDiscountAmount);
            Clear(POSInvDiscAmount);
            Clear(InfoCodeDiscountAmount);
            Clear(POSLineDiscAmount);
            Clear(PeriodicDiscAmount);
            Clear(CouponDiscAmount);
            Clear(POSLineDiscOfferAmount);
            Clear(POSTotalDiscOfferAmount);
            Clear(POSTenderDiscOfferAmount);
            Clear(CustDiscountVATAmount);
            Clear(POSInvDiscVATAmount);
            Clear(InfoCodeDiscVATAmount);
            Clear(POSLineDiscVATAmount);
            Clear(PeriodicDiscVATAmount);
            Clear(CouponDiscVATAmount);
            Clear(POSLineDiscOfferVATAmount);
            Clear(POSTotalDiscOfferVATAmount);
            Clear(POSTenderDiscOfferVATAmount);

            if BackOfficeSetup."Post Cust. Disc." then begin
                TmpDiscAmt := GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::Customer);
                if TmpDiscAmt <> 0 then begin
                    GenPostingSetup.TestField("LSC POS Cust. Disc. Account");
                    CustDiscountAmount := Round(TmpDiscAmt / VATFactor);
                    CustDiscountVATAmount := Round(TmpDiscAmt - CustDiscountAmount);
                end;
            end;

            if BackOfficeSetup."Post Total Disc." then begin
                TmpDiscAmt := GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::Total);
                if TmpDiscAmt <> 0 then begin
                    GenPostingSetup.TestField("LSC POS Inv. Disc. Account");
                    POSInvDiscAmount := Round(TransSalesEntry."Total Discount" / VATFactor);
                    POSInvDiscVATAmount := Round(TransSalesEntry."Total Discount" - POSInvDiscAmount);
                end;
            end;

            if BackOfficeSetup."Post Infocode Disc." then begin
                TmpDiscAmt := GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::Infocode);
                if TmpDiscAmt <> 0 then begin
                    GenPostingSetup.TestField("LSC POS InfoCode Disc. Account");
                    InfoCodeDiscountAmount := Round(TmpDiscAmt / VATFactor);
                    InfoCodeDiscVATAmount := Round(TmpDiscAmt - InfoCodeDiscountAmount);
                end;
            end;

            if BackOfficeSetup."Post Line Disc." then begin
                TmpDiscAmt := GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::Line);
                if TmpDiscAmt <> 0 then begin
                    GenPostingSetup.TestField("LSC POS Line Disc. Account");
                    POSLineDiscAmount := Round(TmpDiscAmt / VATFactor);
                    POSLineDiscVATAmount := Round(TmpDiscAmt - POSLineDiscAmount);
                end;
            end;

            if BackOfficeSetup."Post Periodic Disc." then begin
                TmpDiscAmt :=
                  GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::Multibuy) +
                  GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::"Mix&Match") +
                  GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::"Item Point") +
                  GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::"Disc. Offer");
                if TmpDiscAmt <> 0 then begin
                    GenPostingSetup.TestField("LSC POS Periodic Disc. Account");
                    PeriodicDiscAmount := Round(TmpDiscAmt / VATFactor);
                    PeriodicDiscVATAmount := Round(TmpDiscAmt - PeriodicDiscAmount);
                end;
            end;

            if BackOfficeSetup."Post Coupon Disc." then begin
                TmpDiscAmt := GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::Coupon);
                if TmpDiscAmt <> 0 then begin
                    GenPostingSetup.TestField("LSC POS Coup. Disc. Account");
                    CouponDiscAmount := Round(TmpDiscAmt / VATFactor);
                    CouponDiscVATAmount := Round(TmpDiscAmt - CouponDiscAmount);
                end;
            end;

            if BackOfficeSetup."Post Line Disc. Offer" then begin
                TmpDiscAmt := GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::"Line Discount");
                if TmpDiscAmt <> 0 then begin
                    GenPostingSetup.TestField("LSC POS Line. Disc. Offer Acc.");
                    POSLineDiscOfferAmount := Round(TmpDiscAmt / VATFactor);
                    POSLineDiscOfferVATAmount := Round(TmpDiscAmt - POSLineDiscOfferAmount);
                end;
            end;

            if BackOfficeSetup."Post Total Disc. Offer" then begin
                TmpDiscAmt := GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::"Total Discount");
                if TmpDiscAmt <> 0 then begin
                    GenPostingSetup.TestField("LSC POS Total Disc. Offer Acc.");
                    POSTotalDiscOfferAmount := Round(TmpDiscAmt / VATFactor);
                    POSTotalDiscOfferVATAmount := Round(TmpDiscAmt - POSTotalDiscOfferAmount);
                end;
            end;

            if BackOfficeSetup."Post Tender Type Disc." then begin
                TmpDiscAmt := GetTransLineDiscAmount(TransDiscEntryTemp, TransSalesEntry, OfferType::"Tender Type");
                if TmpDiscAmt <> 0 then begin
                    GenPostingSetup.TestField("LSC POS Tender Type Disc. Acc.");
                    POSTenderDiscOfferAmount := Round(TmpDiscAmt / VATFactor);
                    POSTenderDiscOfferVATAmount := Round(TmpDiscAmt - POSTenderDiscOfferAmount);
                end;
            end;

            PostingBuffer[1].Amount :=
              PostingBuffer[1].Amount - CustDiscountAmount - POSInvDiscAmount
              - InfoCodeDiscountAmount - POSLineDiscAmount
              - PeriodicDiscAmount - CouponDiscAmount
              - POSLineDiscOfferAmount - POSTotalDiscOfferAmount - POSTenderDiscOfferAmount;

            IsHandled := false;
            OnBeforeCalculatePostingBufferVatAmountsV2(PostingBuffer[1], IsHandled);
            if not IsHandled then begin
                PostingBuffer[1]."VAT Base Amount" := PostingBuffer[1].Amount;
                PostingBuffer[1]."VAT Amount" :=
                  PostingBuffer[1]."VAT Amount" - CustDiscountVATAmount - POSInvDiscVATAmount
                   - InfoCodeDiscVATAmount - POSLineDiscVATAmount
                   - PeriodicDiscVATAmount - CouponDiscVATAmount
                   - POSLineDiscOfferVATAmount - POSTotalDiscOfferVATAmount - POSTenderDiscOfferVATAmount;
            end;

            IsHandled := false;
            OnBeforeUpdLedgerPostingBufferInPostItemSales(PostingBuffer[1], TransSalesEntry, Len, PostingBuffer, VATFactor, TempDimBufNew, TableID, No, IsHandled);
            if not IsHandled then begin
                UpdPostingBuffer();

                if CustDiscountAmount <> 0 then
                    PostDiscountBuffering(Len, GenPostingSetup."LSC POS Cust. Disc. Account", CustDiscountAmount, CustDiscountVATAmount, SalesTypeCode);

                if POSInvDiscAmount <> 0 then
                    PostDiscountBuffering(Len, GenPostingSetup."LSC POS Inv. Disc. Account", POSInvDiscAmount, POSInvDiscVATAmount, SalesTypeCode);

                if InfoCodeDiscountAmount <> 0 then
                    PostDiscountBuffering(Len, GenPostingSetup."LSC POS InfoCode Disc. Account", InfoCodeDiscountAmount, InfoCodeDiscVATAmount, SalesTypeCode);

                if POSLineDiscAmount <> 0 then
                    PostDiscountBuffering(Len, GenPostingSetup."LSC POS Line Disc. Account", POSLineDiscAmount, POSLineDiscVATAmount, SalesTypeCode);

                if PeriodicDiscAmount <> 0 then
                    PostDiscountBuffering(Len, GenPostingSetup."LSC POS Periodic Disc. Account", PeriodicDiscAmount, PeriodicDiscVATAmount, SalesTypeCode);

                if CouponDiscAmount <> 0 then
                    PostDiscountBuffering(Len, GenPostingSetup."LSC POS Coup. Disc. Account", CouponDiscAmount, CouponDiscVATAmount, SalesTypeCode);

                if POSLineDiscOfferAmount <> 0 then
                    PostDiscountBuffering(Len, GenPostingSetup."LSC POS Line. Disc. Offer Acc.", POSLineDiscOfferAmount, POSLineDiscOfferVATAmount, SalesTypeCode);

                if POSTotalDiscOfferAmount <> 0 then
                    PostDiscountBuffering(Len, GenPostingSetup."LSC POS Total Disc. Offer Acc.", POSTotalDiscOfferAmount, POSTotalDiscOfferVATAmount, SalesTypeCode);

                if POSTenderDiscOfferAmount <> 0 then
                    PostDiscountBuffering(Len, GenPostingSetup."LSC POS Tender Type Disc. Acc.", POSTenderDiscOfferAmount, POSTenderDiscOfferVATAmount, SalesTypeCode);
            end;
        end;

        TransSalesEntryStatus.Get(TransSalesEntry."Store No.", TransSalesEntry."POS Terminal No.", TransSalesEntry."Transaction No.", TransSalesEntry."Line No.");

        if (TransSalesEntryStatus.Status <> TransSalesEntryStatus.Status::"Items Posted") or
           ((TransSalesEntryStatus.Status = TransSalesEntryStatus.Status::"Items Posted") and (glUndoItemPosting))
        then begin
            if (TransSalesEntryStatus.Status <> TransSalesEntryStatus.Status::"Items Posted") and (Item."Service Item Group" <> '') then
                CreateServItemOnTransSalesEnt(Transaction, TransSalesEntry, Statement."No.");

            ItemEntryNo := FindDimensions(TempDimBufNew);
            if ItemEntryNo = 0 then
                ItemEntryNo := InsertDimensions(TempDimBufNew);

            Clear(ItemPostingBuffer[1]);
            ItemPostingBuffer[1].Type := ItemPostingBuffer[1].Type::Sales;

            ItemPostingBuffer[1]."Serial No." := TransSalesEntry."Serial No.";
            ItemPostingBuffer[1]."Lot No." := TransSalesEntry."Lot No.";
            ItemPostingBuffer[1]."Expiration Date" := TransSalesEntry."Expiration Date";
            ItemPostingBuffer[1]."Item No." := TransSalesEntry."Item No.";
            ItemPostingBuffer[1]."Entry No." := ItemEntryNo;

            if TransSalesEntry."Gen. Bus. Posting Group" <> '' then
                ItemPostingBuffer[1]."Gen. Bus. Posting Group" := TransSalesEntry."Gen. Bus. Posting Group"
            else
                ItemPostingBuffer[1]."Gen. Bus. Posting Group" := Store."Gen. Bus. Post. Gr.";
            if TransSalesEntry."Gen. Prod. Posting Group" <> '' then
                ItemPostingBuffer[1]."Gen. Prod. Posting Group" := TransSalesEntry."Gen. Prod. Posting Group"
            else
                ItemPostingBuffer[1]."Gen. Prod. Posting Group" := Item."Gen. Prod. Posting Group";

            LocCode := Store."Location Code";
            if (SalesTypeCode <> '') and (TransSalesEntry."Refund Qty." = 0) then
                if SalesType2.Get(SalesTypeCode) then
                    if SalesType2."Location Code" <> '' then
                        LocCode := SalesType2."Location Code";
            ItemPostingBuffer[1]."Location Code" := LocCode;
            ItemPostingBuffer[1]."Department Code" := Store."Global Dimension 1 Code";
            ItemPostingBuffer[1]."Document No." := DocNumber;
            if glUndoItemPosting then
                ItemPostingBuffer[1].Quantity := TransSalesEntry.Quantity
            else
                ItemPostingBuffer[1].Quantity := -TransSalesEntry.Quantity;
            ItemPostingBuffer[1]."Neg. Qty" := ItemPostingBuffer[1].Quantity <= 0;
            ItemPostingBuffer[1].Amount := -TransSalesEntry."Net Amount";
            ItemPostingBuffer[1]."Cost Amount" := -TransSalesEntry."Cost Amount";
            ItemPostingBuffer[1]."Offer No." := TransSalesEntry."Periodic Disc. Group";

            ItemPostingBuffer[1]."Promotion No." := TransSalesEntry."Promotion No.";
            ItemPostingBuffer[1]."Sales Type" := SalesTypeCode;
            ItemPostingBuffer[1]."Inv. Discount Amount" := Round(TransSalesEntry."Discount Amount" / VATFactor);

            OnBeforeCreateDiscBufferInPostItemSalesV2(ItemPostingBuffer, Transaction, TransSalesEntry);
            CreateDiscBuffer(TransDiscEntryTemp, TransSalesEntry, VATFactor);

            if glUndoItemPosting then begin
                ItemPostingBuffer[1].Amount := -ItemPostingBuffer[1].Amount;
                ItemPostingBuffer[1]."Cost Amount" := -ItemPostingBuffer[1]."Cost Amount";
                ItemPostingBuffer[1]."Inv. Discount Amount" := -ItemPostingBuffer[1]."Inv. Discount Amount";
                ItemPostingBuffer[1]."Line Discount Amount" := -ItemPostingBuffer[1]."Line Discount Amount";
                OnBeforeRevertSignCurrDiscBufferInPostItemSalesV2(ItemPostingBuffer[1]);
                DiscLedgerMgt.RevertSignCurrDiscBuffer();
            end;
            if TransSalesEntry."Variant Code" <> '' then
                ItemPostingBuffer[1]."Source No." := TransSalesEntry."Variant Code";
            if Transaction."To Account" then
                ItemPostingBuffer[1]."Customer No." := CustomerRec."No.";

            if BackOfficeSetup."Item Posting Date" = "LSC Item Posting Date"::"Transaction Date" then
                ItemPostingBuffer[1].Date := TransSalesEntry.Date
            else
                ItemPostingBuffer[1].Date := Statement."Posting Date";

            if Transaction."Trans. Currency" <> '' then begin
                CurrencyFactor := CurrencyExchRate.ExchangeRate(ItemPostingBuffer[1].Date, Transaction."Trans. Currency");

                ItemPostingBuffer[1].Amount :=
                  Round(CurrencyExchRate.ExchangeAmtFCYToLCY(
                    ItemPostingBuffer[1].Date, Transaction."Trans. Currency", ItemPostingBuffer[1].Amount, CurrencyFactor));
                ItemPostingBuffer[1]."Cost Amount" :=
                  Round(CurrencyExchRate.ExchangeAmtFCYToLCY(
                    ItemPostingBuffer[1].Date, Transaction."Trans. Currency", ItemPostingBuffer[1]."Cost Amount", CurrencyFactor));
                ItemPostingBuffer[1]."Inv. Discount Amount" :=
                  Round(CurrencyExchRate.ExchangeAmtFCYToLCY(
                    ItemPostingBuffer[1].Date, Transaction."Trans. Currency", ItemPostingBuffer[1]."Inv. Discount Amount", CurrencyFactor));
                ItemPostingBuffer[1]."Line Discount Amount" :=
                  Round(CurrencyExchRate.ExchangeAmtFCYToLCY(
                    ItemPostingBuffer[1].Date, Transaction."Trans. Currency", ItemPostingBuffer[1]."Line Discount Amount", CurrencyFactor));
                DiscLedgerMgt.ExchFCYToLCYCurrDiscBuffer(ItemPostingBuffer[1].Date, Transaction."Trans. Currency", CurrencyFactor);
            end;

            if (TransSalesEntry."Sales Staff" <> '') and Staff.Get(TransSalesEntry."Sales Staff") and (Staff."Sales Person" <> '') then
                ItemPostingBuffer[1]."Salesperson Code" := Staff."Sales Person";

            Clear(PostingException);
            if TransSalesEntry."Posting Exception Key" <> '' then
                PostingExceptionUtility.FindItremPostExSetupByKey(TransSalesEntry."Posting Exception Key", PostingException);
            /*
            if ExplodeItem(Item, Transaction, TransSalesEntry, FuelItem) then begin
                if (Item."LSC Upd Cost and Weight w/Post") or FuelItem then begin
                    if BackOfficeSetup."Item Posting Date" = "LSC Item Posting Date"::"Transaction Date" then
                        BOMItemBuffer.Date := TransSalesEntry.Date
                    else
                        BOMItemBuffer.Date := Statement."Posting Date";
                    if not BOMItemBuffer.Get('', '', TransSalesEntry."Item No.", '', BOMItemBuffer.Date, false) then begin
                        BOMItemBuffer.Init();
                        BOMItemBuffer."Item No." := TransSalesEntry."Item No.";
                        if BackOfficeSetup."Item Posting Date" = "LSC Item Posting Date"::"Transaction Date" then
                            BOMItemBuffer.Date := TransSalesEntry.Date
                        else
                            BOMItemBuffer.Date := Statement."Posting Date";
                        BOMItemBuffer.Insert;
                    end;
                end;
                if ((Item."LSC Explode BOM in Statem Post") and (Item."LSC BOM Type" <> Item."LSC BOM Type"::Prepack)) or
                   (FuelItem and (TransSalesEntry."Variant Code" <> ''))
                then begin
                    BOMPostingBuffer[1]."Document No." := DocNumber;
                    if Transaction."To Account" then
                        BOMPostingBuffer[1]."Customer No." := CustomerRec."No.";
                    BOMPostingBuffer[1]."Item No." := TransSalesEntry."Item No.";
                    BOMPostingBuffer[1].Quantity := -TransSalesEntry.Quantity;
                    BOMPostingBuffer[1]."Neg. Qty" := BOMPostingBuffer[1].Quantity <= 0;
                    BOMPostingBuffer[1]."Location Code" := LocCode;
                    if (PostingException.Key <> '') and (PostingException."Transfer Process" = PostingException."Transfer Process"::Transfer) then
                        BOMPostingBuffer[1]."Location Code" := PostingException."Sourcing Location Code";
                    BOMPostingBuffer[1]."Serial No." := '';
                    BOMPostingBuffer[1]."Lot No." := '';
                    BOMPostingBuffer[1]."Expiration Date" := 0D;
                    BOMPostingBuffer[1]."Variant Code" := TransSalesEntry."Variant Code";
                    BOMPostingBuffer[1]."Sales Type" := SalesTypeCode;
                    if BackOfficeSetup."Item Posting Date" = "LSC Item Posting Date"::"Transaction Date" then
                        BOMPostingBuffer[1].Date := TransSalesEntry.Date
                    else
                        BOMPostingBuffer[1].Date := Statement."Posting Date";
                    OnBeforeInsertBOMPostingBufferSales(BOMPostingBuffer[1], TransSalesEntry);
                    UpdBOMPostingBuffer;
                end;
            end;
            */

            if (PostingException.Key <> '') and (PostingException."Transfer Process" = PostingException."Transfer Process"::Transfer) then
                ProcessItemAdjustPostBuffer(PostingException);
            OnBeforeInsertItemPostingBufferSalesV2(ItemPostingBuffer[1], TransSalesEntry, Transaction);
            UpdItemPostingBuffer();
        end;
        OnAfterPostItemSales(TransSalesEntry, Transaction, Statement);
    end;

    /*
    internal procedure ExplodeItem(var Item: Record Item; var Transaction: Record "LSC Transaction Header"; var TransSalesEntry: Record "LSC Trans. Sales Entry"; FuelItem: Boolean): Boolean
    begin
        exit(ExplodeItem(Item, Transaction, TransSalesEntry, FuelItem, this));
    end;
    */

    /*
    internal procedure ExplodeItem(var Item: Record Item; var Transaction: Record "LSC Transaction Header"; var TransSalesEntry: Record "LSC Trans. Sales Entry"; FuelItem: Boolean; Controller: Interface "LSC IStatementPostController"): Boolean
    begin
        if Controller.SkipExplodingBOMItemOnRefund(Item, TransSalesEntry, Transaction) then
            exit(false);
        if Controller.ExplodeBOMItem(Item) then
            exit(true);
        if Controller.ExplodeFuelItem(TransSalesEntry, FuelItem) then
            exit(true);
        exit(false);
    end;
    */

    internal procedure ExplodeBOMItem(var Item: Record Item): Boolean
    begin
        Item.CalcFields("Assembly BOM");

        exit(Item."Assembly BOM");
    end;

    internal procedure SkipExplodingBOMItemOnRefund(var Item: Record Item; var TransSalesEntry: Record "LSC Trans. Sales Entry"; var Transaction: Record "LSC Transaction Header"): Boolean
    var
        IsReturnSale: Boolean;
    begin
        if not Item."LSC Skip Exp Bom Item Post Ref" then
            exit(false);

        IF TransSalesEntry."Excluded BOM Line No." <> 0 then
            exit(false);

        IsReturnSale := Transaction."Sale Is Return Sale";

        if not IsReturnSale then
            IsReturnSale := TransSalesEntry."Quantity" > 0;

        exit(IsReturnSale);
    end;

    internal procedure ExplodeFuelItem(var TransSalesEntry: Record "LSC Trans. Sales Entry"; FuelItem: Boolean): Boolean
    begin
        if not FuelItem then
            exit(false);
        if TransSalesEntry."Variant Code" = '' then
            exit(false);
        exit(true);
    end;

    internal procedure PostIncomeExpLine(DocNumber: Code[20])
    var
        COSetup: Record "LSC Customer Order Setup";
        GlobalDimension1Code: Code[20];
        GlobalDimension2Code: Code[20];
        EntryNo: Integer;
        Len: Integer;
        Handled: Boolean;
        IsPrepaymentInvoiceMarked: Boolean;
    begin
        //!!!
        if Transaction."Customer Order ID" <> '' then
            if COPrepaymentInvoiceMan.IsCustomerOrderPrepaymentInvoiceMarked(Transaction."Customer Order ID") then
                IsPrepaymentInvoiceMarked := true;


        IncomeExpenseAcc.Get(Store."No.", TransIncomeExpenseEntry."No.");

        OnBeforePostIncomeExpLine(TransIncomeExpenseEntry, Transaction, Statement, DocNumber, PostingBuffer[1], Handled);
        if Handled then
            exit;

        Clear(TableID);
        Clear(No);

        TableID[1] := Database::"LSC Store";
        No[1] := Store."No.";
        TableID[2] := Database::"G/L Account";

        if IsPrepaymentInvoiceMarked then
            No[2] := COPrepaymentInvoiceMan.GetPrepaymentInvoiceAccountNo(Transaction."Customer Order ID")
        else
            No[2] := IncomeExpenseAcc."G/L Account";

        Len := 2;
        if Transaction."Customer No." <> '' then begin
            TableID[3] := Database::Customer;
            No[3] := Transaction."Customer No.";
            Len := 3;
        end;
        GetDefaultDim(
            TableID, No, BackOfficeSetup."Source Code", GlobalDimension1Code,
            GlobalDimension2Code, Len);

        EntryNo := FindDimensions(TempDimBufNew);
        if EntryNo = 0 then
            EntryNo := InsertDimensions(TempDimBufNew);

        Clear(PostingBuffer[1]);
        PostingBuffer[1].Type := PostingBuffer[1].Type::"G/L Account";
        if Transaction."To Account" then
            PostingBuffer[1]."Customer No." := CustomerRec."No.";
        if IsPrepaymentInvoiceMarked then begin
            PostingBuffer[1]."G/L Account" := No[2];
            GLAccount2.Get(PostingBuffer[1]."G/L Account");
            PostingBuffer[1]."Customer Order ID" := Transaction."Customer Order ID";
        end else begin
            IncomeExpenseAcc.TestField(IncomeExpenseAcc."G/L Account");
            GLAccount2.Get(IncomeExpenseAcc."G/L Account");
            PostingBuffer[1]."G/L Account" := IncomeExpenseAcc."G/L Account";
        end;
        PostingBuffer[1]."Gen. Business Posting Group" := GLAccount2."Gen. Bus. Posting Group";
        PostingBuffer[1]."Gen. Product Posting Group" := GLAccount2."Gen. Prod. Posting Group";
        PostingBuffer[1]."VAT Business Posting Group" := GLAccount2."VAT Bus. Posting Group";
        PostingBuffer[1]."VAT Product Posting Group" := GLAccount2."VAT Prod. Posting Group";
        PostingBuffer[1]."Entry No." := EntryNo;
        PostingBuffer[1]."Department Code" := GlobalDimension1Code;
        PostingBuffer[1]."Project Code" := GlobalDimension2Code;
        PostingBuffer[1]."Currency Code" := Transaction."Trans. Currency";
        PostingBuffer[1]."Document No." := DocNumber;
        if COSetup.Get() then
            if COSetup."Split IncExp Entries Statement" then
                PostingBuffer[1]."Customer Order ID" := Transaction."Customer Order ID";

        PostingBuffer[1]."VAT Calculation Type" := PostingBuffer[1]."VAT Calculation Type"::"Normal VAT";
        VATPostingSetup.Get(GLAccount2."VAT Bus. Posting Group", GLAccount2."VAT Prod. Posting Group");
        IncExpVATPercent := VATPostingSetup."VAT %";
        PostingBuffer[1]."VAT Amount" := TransIncomeExpenseEntry."VAT Amount";
        PostingBuffer[1].Amount := TransIncomeExpenseEntry.Amount - PostingBuffer[1]."VAT Amount";
        PostingBuffer[1]."VAT Base Amount" := PostingBuffer[1].Amount;

        TransIncomeExpenseEntry."Statement No." := Statement."Posting No.";
        OnBeforeModifyLedgerPostingBufferInPostIncomeExpLine2(PostingBuffer[1], TransIncomeExpenseEntry, Transaction);
        TransIncomeExpenseEntry.Modify();

        OnBeforeUpdLedgerPostingBufferInPostIncomeExpLine2(PostingBuffer[1], TransIncomeExpenseEntry, TempDimBufPost);

        UpdPostingBuffer();
    end;

    procedure PostDataEntryReverseVAT(DocNumber: Code[20])
    var
        SalesType2: Record "LSC Sales Type";
        PostingException: Record "LSC Posting Exception";
        Infocode: Record "LSC Infocode";
        DataEntry: Record "LSC POS Data Entry";
        OriginalTransSalesEntry: Record "LSC Trans. Sales Entry";
        OriginalIncomeEntry: Record "LSC Trans. Inc./Exp. Entry";
        OriginalInfocodeEntry: Record "LSC Trans. Infocode Entry";
        OriginalTransHeader: Record "LSC Transaction Header";
        IncExpAccount: Record "LSC Income/Expense Account";
        IncomeGLAccount: Record "G/L Account";
        GlobalDimension1Code: Code[20];
        GlobalDimension2Code: Code[20];
        LocCode: Code[10];
        SalesTypeCode: Code[20];
        GenBusPostingGroup: Code[20];
        GenProdPostingGroup: Code[20];
        VATBusPostingGroup: Code[20];
        VATProdPostingGroup: Code[20];
        AccountNo: Code[20];
        AmountToUse: Decimal;
        VATAmountToUse: Decimal;
        NetAmountToUse: Decimal;
        VATPercentageToUse: Decimal;
        EntryNo: Integer;
        Len: Integer;
        UsageLabel: Label 'Usage';
        IsHandled: Boolean;
    begin
        OnBeforePostDataEntryReverseVAT(DocNumber, Statement, Transaction, TransInfocodeEntry, ItemPostingBuffer[1], PostingBuffer[1], IsHandled);
        if IsHandled then
            exit;

        Infocode.SetRange(Code, TransInfocodeEntry.Infocode);
        Infocode.SetRange(Type, Infocode.Type::"Apply To Entry");
        Infocode.SetFilter("Data Entry Type", '<>%1', '');
        if not Infocode.FindFirst() then
            exit;

        if DataEntry.Get(Infocode."Data Entry Type", TransInfocodeEntry.Information) then begin
            OriginalTransHeader.SetRange("Store No.", DataEntry."Created in Store No.");
            OriginalTransHeader.SetRange("Receipt No.", DataEntry."Created by Receipt No.");
            if not OriginalTransHeader.FindFirst() then
                exit;

            OriginalInfocodeEntry.SetRange("Store No.", OriginalTransHeader."Store No.");
            OriginalInfocodeEntry.SetRange("Transaction No.", OriginalTransHeader."Transaction No.");
            OriginalInfocodeEntry.SetRange("POS Terminal No.", OriginalTransHeader."POS Terminal No.");
            OriginalInfocodeEntry.SetRange("Type of Input", OriginalInfocodeEntry."Type of Input"::"Create Data Entry");
            OriginalInfocodeEntry.SetRange(Information, TransInfocodeEntry.Information);
            if not OriginalInfocodeEntry.FindFirst() then
                exit;

            if OriginalInfocodeEntry."Transaction Type" = OriginalInfocodeEntry."Transaction Type"::"Sales Entry" then begin
                OriginalTransSalesEntry.Reset();
                OriginalTransSalesEntry.SetRange("Receipt No.", DataEntry."Created by Receipt No.");
                OriginalTransSalesEntry.SetRange("Line No.", DataEntry."Created by Line No.");
                OriginalTransSalesEntry.SetRange("Store No.", DataEntry."Created in Store No.");
                if not OriginalTransSalesEntry.FindFirst() then
                    exit;

                VATBusPostingGroup := OriginalTransSalesEntry."VAT Bus. Posting Group";
                VATProdPostingGroup := OriginalTransSalesEntry."VAT Prod. Posting Group";
                GenBusPostingGroup := OriginalTransSalesEntry."Gen. Bus. Posting Group";
                GenProdPostingGroup := OriginalTransSalesEntry."Gen. Prod. Posting Group";

                if (abs(OriginalTransSalesEntry."Net Amount") + abs(OriginalTransSalesEntry."VAT Amount")) > 0 then
                    VATPercentageToUse := abs(OriginalTransSalesEntry."VAT Amount" / (abs(OriginalTransSalesEntry."Net Amount") + abs(OriginalTransSalesEntry."VAT Amount")));

                GetItem(OriginalTransSalesEntry."Item No.", OriginalTransSalesEntry, Item);

                if Item.Type = Item.Type::Inventory then begin
                    OnBeforePostItemInventory(OriginalTransSalesEntry, Item, Transaction, Statement, DocNumber, ItemPostingBuffer[1], IsHandled);
                    if not IsHandled then begin
                        AmountToUse := TransInfocodeEntry.Amount;
                        VATAmountToUse := AmountToUse * VATPercentageToUse;
                        NetAmountToUse := AmountToUse - VATAmountToUse;
                        Clear(ItemPostingBuffer[1]);
                        ItemPostingBuffer[1].Type := ItemPostingBuffer[1].Type::Sales;

                        ItemPostingBuffer[1]."Item No." := OriginalTransSalesEntry."Item No.";

                        if OriginalTransSalesEntry."Gen. Bus. Posting Group" <> '' then
                            ItemPostingBuffer[1]."Gen. Bus. Posting Group" := OriginalTransSalesEntry."Gen. Bus. Posting Group"
                        else
                            ItemPostingBuffer[1]."Gen. Bus. Posting Group" := Store."Gen. Bus. Post. Gr.";
                        if OriginalTransSalesEntry."Gen. Prod. Posting Group" <> '' then
                            ItemPostingBuffer[1]."Gen. Prod. Posting Group" := OriginalTransSalesEntry."Gen. Prod. Posting Group"
                        else
                            ItemPostingBuffer[1]."Gen. Prod. Posting Group" := Item."Gen. Prod. Posting Group";

                        LocCode := Store."Location Code";
                        if (SalesTypeCode <> '') and (OriginalTransSalesEntry."Refund Qty." = 0) then
                            if SalesType2.Get(SalesTypeCode) then
                                if SalesType2."Location Code" <> '' then
                                    LocCode := SalesType2."Location Code";
                        ItemPostingBuffer[1]."Location Code" := LocCode;
                        ItemPostingBuffer[1]."Department Code" := Store."Global Dimension 1 Code";
                        ItemPostingBuffer[1]."Document No." := DocNumber;
                        if glUndoItemPosting then
                            ItemPostingBuffer[1].Quantity := -TransInfocodeEntry.Quantity
                        else
                            ItemPostingBuffer[1].Quantity := TransSalesEntry.Quantity;
                        ItemPostingBuffer[1]."Neg. Qty" := ItemPostingBuffer[1].Quantity <= 0;
                        ItemPostingBuffer[1].Amount := NetAmountToUse;
                        ItemPostingBuffer[1]."Cost Amount" := TransInfocodeEntry."Cost Amount";
                        ItemPostingBuffer[1]."Sales Type" := SalesTypeCode;

                        if Transaction."To Account" then
                            ItemPostingBuffer[1]."Customer No." := CustomerRec."No.";

                        if BackOfficeSetup."Item Posting Date" = "LSC Item Posting Date"::"Transaction Date" then
                            ItemPostingBuffer[1].Date := TransInfocodeEntry.Date
                        else
                            ItemPostingBuffer[1].Date := Statement."Posting Date";

                        Clear(PostingException);
                        if OriginalTransSalesEntry."Posting Exception Key" <> '' then
                            PostingExceptionUtility.FindItremPostExSetupByKey(OriginalTransSalesEntry."Posting Exception Key", PostingException);

                        if (PostingException.Key <> '') and (PostingException."Transfer Process" = PostingException."Transfer Process"::Transfer) then
                            ProcessItemAdjustPostBuffer(PostingException);

                        UpdItemPostingBuffer();
                    end;
                end;

                AmountToUse := TransInfocodeEntry.Amount;

                VATAmountToUse := AmountToUse * VATPercentageToUse;
                NetAmountToUse := AmountToUse - VATAmountToUse;

                if VATBusPostingGroup = '' then
                    VATBusPostingGroup := Transaction."VAT Bus.Posting Group";
                if (VATProdPostingGroup = '') and (TransInfocodeEntry."Transaction Type" = TransInfocodeEntry."Transaction Type"::"Sales Entry") then
                    VATProdPostingGroup := Item."VAT Prod. Posting Group";
                if not VATPostingSetup.Get(VATBusPostingGroup, VATProdPostingGroup) then
                    exit;

                if GenBusPostingGroup = '' then
                    if Transaction."To Account" then
                        GenBusPostingGroup := CustomerRec."Gen. Bus. Posting Group"
                    else
                        GenBusPostingGroup := Store."Gen. Bus. Post. Gr.";

                if (GenProdPostingGroup = '') and (TransInfocodeEntry."Transaction Type" = TransInfocodeEntry."Transaction Type"::"Sales Entry") then
                    GenProdPostingGroup := Item."Gen. Prod. Posting Group";

                if not GenPostingSetup.Get(GenBusPostingGroup, GenProdPostingGroup) then
                    exit;

                Clear(TableID);
                Clear(No);

                TableID[1] := Database::Item;
                No[1] := Item."No.";
                TableID[2] := Database::"LSC Store";
                No[2] := Store."No.";
                TableID[3] := Database::"G/L Account";

                if Transaction."Sale Is Return Sale" then
                    No[3] := GenPostingSetup."Sales Credit Memo Account"
                else
                    No[3] := GenPostingSetup."Sales Account";

                Len := 3;
                if Transaction."Customer No." <> '' then begin
                    TableID[4] := Database::Customer;
                    No[4] := Transaction."Customer No.";
                    Len := 4;
                end;

                SalesTypeCode := Transaction."Sales Type";
                if Transaction."Sales Type" <> '' then
                    SalesTypeCode := Transaction."Sales Type";

                if SalesTypeCode <> '' then begin
                    Len := Len + 1;
                    TableID[Len] := Database::"LSC Sales Type";
                    No[Len] := SalesTypeCode;
                end;

                OnBeforeGetDefaultDimInPostItemSales(Transaction, TransSalesEntry, TableID, No, Len);
                GetDefaultDim(
                    TableID, No, BackOfficeSetup."Source Code", GlobalDimension1Code,
                    GlobalDimension2Code, Len);

                EntryNo := FindDimensions(TempDimBufNew);
                if EntryNo = 0 then begin
                    EntryNo := InsertDimensions(TempDimBufNew);
                    if EntryNo = 0 then
                        EntryNo := 1;
                end;

                Clear(PostingBuffer[1]);
                PostingBuffer[1].Type := PostingBuffer[1].Type::Item;
                GenPostingSetup.TestField("Sales Account");
                if Transaction."To Account" then
                    PostingBuffer[1]."Customer No." := CustomerRec."No.";
                PostingBuffer[1]."Entry No." := EntryNo;
                PostingBuffer[1]."G/L Account" := GenPostingSetup."Sales Account";
                PostingBuffer[1]."Gen. Business Posting Group" := GenPostingSetup."Gen. Bus. Posting Group";
                PostingBuffer[1]."Gen. Product Posting Group" := GenPostingSetup."Gen. Prod. Posting Group";
                PostingBuffer[1]."VAT Business Posting Group" := VATPostingSetup."VAT Bus. Posting Group";
                PostingBuffer[1]."VAT Product Posting Group" := VATPostingSetup."VAT Prod. Posting Group";
                PostingBuffer[1]."Department Code" := GlobalDimension1Code;
                PostingBuffer[1]."Project Code" := GlobalDimension2Code;
                PostingBuffer[1]."Currency Code" := Transaction."Trans. Currency";
                PostingBuffer[1]."Document No." := DocNumber;
                PostingBuffer[1].Amount := (AmountToUse - VATAmountToUse);
                PostingBuffer[1]."VAT Base Amount" := (AmountToUse - VATAmountToUse);
                PostingBuffer[1]."VAT Amount" := VATAmountToUSe;
                PostingBuffer[1]."Reverse VAT" := true;
                OnBeforeUpdatePostingBufferSalesEntry(PostingBuffer[1], OriginalTransSalesEntry);
                UpdPostingBuffer();
            end
            else
                if OriginalInfocodeEntry."Transaction Type" = OriginalInfocodeEntry."Transaction Type"::"Income/Expense Entry" then begin
                    OriginalIncomeEntry.Reset();
                    OriginalIncomeEntry.SetRange("Receipt  No.", DataEntry."Created by Receipt No.");
                    OriginalIncomeEntry.SetRange("Line No.", DataEntry."Created by Line No.");
                    OriginalIncomeEntry.SetRange("Store No.", DataEntry."Created in Store No.");
                    if not OriginalIncomeEntry.FindFirst() then
                        exit;

                    if IncExpAccount.Get(OriginalIncomeEntry."Store No.", OriginalIncomeEntry."No.") then
                        if IncomeGLAccount.Get(IncExpAccount."G/L Account") then begin
                            VATBusPostingGroup := IncomeGLAccount."VAT Bus. Posting Group";
                            VATProdPostingGroup := IncomeGLAccount."VAT Prod. Posting Group";
                            GenBusPostingGroup := IncomeGLAccount."Gen. Bus. Posting Group";
                            GenProdPostingGroup := IncomeGLAccount."Gen. Prod. Posting Group";
                        end
                        else
                            exit;
                    if (abs(OriginalIncomeEntry."Net Amount") + abs(OriginalIncomeEntry."VAT Amount")) > 0 then
                        VATPercentageToUse := abs(OriginalIncomeEntry."VAT Amount" / (abs(OriginalIncomeEntry."Net Amount") + abs(OriginalIncomeEntry."VAT Amount")));

                    AmountToUse := TransInfocodeEntry.Amount;

                    VATAmountToUse := AmountToUse * VATPercentageToUse;
                    NetAmountToUse := AmountToUse - VATAmountToUse;

                    Clear(TableID);
                    Clear(No);

                    TableID[1] := Database::"LSC Store";
                    No[1] := Store."No.";
                    TableID[2] := Database::"G/L Account";
                    No[2] := IncExpAccount."G/L Account";
                    Len := 2;
                    if Transaction."Customer No." <> '' then begin
                        TableID[3] := Database::Customer;
                        No[3] := Transaction."Customer No.";
                        Len := 3;
                    end;
                    GetDefaultDim(
                        TableID, No, BackOfficeSetup."Source Code", GlobalDimension1Code,
                        GlobalDimension2Code, Len);

                    EntryNo := FindDimensions(TempDimBufNew);
                    if EntryNo = 0 then begin
                        EntryNo := InsertDimensions(TempDimBufNew);
                        if EntryNo = 0 then
                            EntryNo := 1;
                    end;

                    Clear(PostingBuffer[1]);
                    PostingBuffer[1].Type := PostingBuffer[1].Type::"G/L Account";
                    IncExpAccount.TestField(IncExpAccount."G/L Account");
                    if Transaction."To Account" then
                        PostingBuffer[1]."Customer No." := CustomerRec."No.";
                    PostingBuffer[1]."Entry No." := EntryNo;
                    PostingBuffer[1]."G/L Account" := IncExpAccount."G/L Account";
                    PostingBuffer[1]."Gen. Business Posting Group" := GenBusPostingGroup;
                    PostingBuffer[1]."Gen. Product Posting Group" := GenProdPostingGroup;
                    PostingBuffer[1]."VAT Business Posting Group" := VATBusPostingGroup;
                    PostingBuffer[1]."VAT Product Posting Group" := VATProdPostingGroup;
                    PostingBuffer[1]."Department Code" := GlobalDimension1Code;
                    PostingBuffer[1]."Project Code" := GlobalDimension2Code;
                    PostingBuffer[1]."Currency Code" := Transaction."Trans. Currency";
                    PostingBuffer[1]."Document No." := DocNumber;
                    PostingBuffer[1].Amount := (AmountToUse - VATAmountToUse);
                    PostingBuffer[1]."VAT Base Amount" := (AmountToUse - VATAmountToUse);
                    PostingBuffer[1]."VAT Amount" := VATAmountToUSe;
                    PostingBuffer[1]."Reverse VAT" := true;
                    OnBeforeUpdatePostingBufferPaymentEntry(PostingBuffer[1], OriginalTransSalesEntry);
                    UpdPostingBuffer();
                end
                else
                    exit;
            TenderType.Get(Store."No.", TransInfocodeEntry."Source Code");
            if not (TenderType."Function" = TenderType."Function"::Customer) then begin
                TenderType.TestField("Account No.");
                TenderType.TestField("Difference G/L Acc.");
            end;

            DiffGLAccountNumber := TenderType."Difference G/L Acc.";

            Clear(PostingBuffer[1]);
            if TenderType."Account Type" = TenderType."Account Type"::"G/L Account" then
                PostingBuffer[1].Type := PostingBuffer[1].Type::"G/L Account"
            else
                PostingBuffer[1].Type := PostingBuffer[1].Type::"Bank Account";
            PostingBuffer[1]."Entry No." := EntryNo;
            PostingBuffer[1]."G/L Account" := TenderType."Account No.";
            PostingBuffer[1]."Payment Posting Description" := StrSubstNo('%1 - %2', TenderType.Description, UsageLabel);
            PostingBuffer[1]."Department Code" := GlobalDimension1Code;
            PostingBuffer[1]."Project Code" := GlobalDimension2Code;
            PostingBuffer[1]."Document No." := DocNumber;
            PostingBuffer[1].Amount := -AmountToUse;
            PostingBuffer[1]."VAT Base Amount" := 0;
            PostingBuffer[1]."VAT Amount" := 0;
            PostingBuffer[1]."Reverse VAT" := true;
            UpdPostingBuffer();
        end;
    end;

    local procedure PostCOAmountToBeRefunded(DocNumber: Code[20])
    var
        GlobalDimension1Code: Code[20];
        GlobalDimension2Code: Code[20];
        EntryNo: Integer;
        Len: Integer;
        RefundBalanceAccountMissing: Label '%1 setup missing for Store %2';
    begin
        if TransactionStatus."Amount to be Refunded" = 0 then
            exit;

        Store.Get(TransactionStatus."Store No.");
        if not IncomeExpenseAcc.Get(Store."No.", Store."Customer Order Refund Acc") then
            Error('%1', StrSubstNo(RefundBalanceAccountMissing, Store.FieldCaption("Customer Order Refund Acc"), Store."No."));

        Clear(TableID);
        Clear(No);

        TableID[1] := Database::"LSC Store";
        No[1] := Store."No.";
        TableID[2] := Database::"G/L Account";
        No[2] := IncomeExpenseAcc."G/L Account";
        Len := 2;

        if Transaction."Customer No." <> '' then begin
            TableID[3] := Database::Customer;
            No[3] := Transaction."Customer No.";
            Len := 3;
        end;

        GetDefaultDim(
            TableID, No, BackOfficeSetup."Source Code", GlobalDimension1Code,
            GlobalDimension2Code, Len);

        EntryNo := FindDimensions(TempDimBufNew);
        if EntryNo = 0 then
            EntryNo := InsertDimensions(TempDimBufNew);

        Clear(PostingBuffer[1]);
        PostingBuffer[1].Type := PostingBuffer[1].Type::"G/L Account";
        IncomeExpenseAcc.TestField(IncomeExpenseAcc."G/L Account");
        GLAccount2.Get(IncomeExpenseAcc."G/L Account");
        if Transaction."To Account" then
            PostingBuffer[1]."Customer No." := CustomerRec."No.";
        PostingBuffer[1]."G/L Account" := IncomeExpenseAcc."G/L Account";
        PostingBuffer[1]."Gen. Business Posting Group" := GLAccount2."Gen. Bus. Posting Group";
        PostingBuffer[1]."Gen. Product Posting Group" := GLAccount2."Gen. Prod. Posting Group";
        PostingBuffer[1]."VAT Business Posting Group" := GLAccount2."VAT Bus. Posting Group";
        PostingBuffer[1]."VAT Product Posting Group" := GLAccount2."VAT Prod. Posting Group";
        PostingBuffer[1]."Entry No." := EntryNo;
        PostingBuffer[1]."Department Code" := GlobalDimension1Code;
        PostingBuffer[1]."Project Code" := GlobalDimension2Code;
        PostingBuffer[1]."Currency Code" := Transaction."Trans. Currency";
        PostingBuffer[1]."Document No." := DocNumber;
        PostingBuffer[1]."VAT Calculation Type" := PostingBuffer[1]."VAT Calculation Type"::"Normal VAT";
        PostingBuffer[1]."VAT Amount" := 0;
        PostingBuffer[1].Amount := -TransactionStatus."Amount to be Refunded";
        PostingBuffer[1]."VAT Base Amount" := PostingBuffer[1].Amount;

        OnBeforeUpdLedgerPostingBufferInPostIncomeExpLine(PostingBuffer[1]);

        UpdPostingBuffer();
    end;

    internal procedure PostToCustomer(DocNumber: Code[20])
    var
        BlockedCust: Record Customer;
        SellToCustNo: Code[20];
        GenJournlDocumentType: Enum "Gen. Journal Document Type";
        TotalAmountPaid: Decimal;
        AmountToDeposit: Decimal;
        TempUnblocking, IsHandled : Boolean;
    begin
        OnBeforePostToCustomer(Statement, Transaction, IsHandled);
        if IsHandled then
            exit;

        if not CustomerRec.Get(Transaction."Customer No.") then
            Error(
              Text031,
              Transaction.FieldCaption("Customer No."), Transaction."Customer No.", CustomerRec.TableCaption);

        SellToCustNo := CustomerRec."No.";

        if CustomerRec."Bill-to Customer No." <> '' then
            if not CustomerRec.Get(CustomerRec."Bill-to Customer No.") then
                Error(
                  Text031,
                  CustomerRec.FieldCaption("Bill-to Customer No."),
                  CustomerRec."Bill-to Customer No.", CustomerRec.TableCaption);

        TempUnblocking := false;
        if (CustomerRec.Blocked <> CustomerRec.Blocked::" ") then begin // temporarily unblocked
            BlockedCust.Blocked := CustomerRec.Blocked;
            TempBlockUnBlockCustomer(CustomerRec.Blocked::" ");
            TempUnblocking := true;
        end;

        SetAmountToPost(GenJournlDocumentType, AmountToPost, SkipCLEPosting);
        if Transaction."Customer Order ID" <> '' then
            if AmountToPost <> 0 then
                AmountToPost += -Transaction.Rounded;

        OnAfterSetAmountToPostToCustomer(Transaction, AmountToPost);

        if Transaction."Transaction Type" <> Transaction."Transaction Type"::Payment then
            CreateAndPostToCustomer(DocNumber, GenJournlDocumentType);

        AmountToDeposit := 0;
        OnBeforeCLEPosting(Transaction, SkipCLEPosting, AmountToPost, GenJournlDocumentType);
        if not SkipCLEPosting then  //Customer Ledger Entry posting
            if (AmountToPost <> 0) or (GenJournlDocumentType = GenJournlDocumentType::Payment) then begin
                TotalAmountPaid := CalculateTotalAmountPaid(AmountToDeposit);
                if TotalAmountPaid <> 0 then
                    PostPaymentToCustomer(DocNumber, CustomerRec."No.", TotalAmountPaid, Transaction."Apply to Doc. No.");

                if Transaction."Customer Order ID" <> '' then
                    if AmountToDeposit <> 0 then
                        PostCustomerOrderPayment(SellToCustNo, TotalAmountPaid, AmountToDeposit);

                //!!!
                if COPrepaymentInvoiceMan.IsCustomerOrderPrepaymentInvoiceMarked(Transaction."Customer Order ID") then
                    if (Transaction.Payment = 0) and (Transaction."No. of Items" > 0) then begin
                        TransIncomeExpenseEntry.SetRange("Store No.", Transaction."Store No.");
                        TransIncomeExpenseEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                        TransIncomeExpenseEntry.SetRange("Transaction No.", Transaction."Transaction No.");
                        TransIncomeExpenseEntry.SetRange("To Account", false);
                        if TransIncomeExpenseEntry.FindSet() then begin
                            TransIncomeExpenseEntry.CalcSums("Amount");
                            if TransIncomeExpenseEntry.Amount <> 0 then
                                PostPaymentToCustomer(DocNumber, CustomerRec."No.", TransIncomeExpenseEntry.Amount, '');
                        end;
                    end;

            end;

        if TempUnblocking then begin
            CustomerRec.Get(CustomerRec."No.");
            CustomerRec.Blocked := BlockedCust.Blocked;
            CustomerRec.Modify();
            TempUnblocking := false;
        end;
    end;

    local procedure CalculateTotalAmountPaid(var AmountToDeposit: Decimal): Decimal
    begin
        if CollectionBySalesOrder(Transaction."Customer Order ID") then begin
            //!!!
            if (Transaction."Amount to Account" = 0) and (Transaction.Payment = -(Transaction."Gross Amount" + Transaction."Income/Exp. Amount")) then
                if COPrepaymentInvoiceMan.IsCustomerOrderPrepaymentInvoiceMarked(Transaction."Customer Order ID") then begin
                    if Transaction."Gross Amount" = 0 then
                        exit(Transaction.Payment)
                    else
                        exit(-Transaction."Gross Amount")
                end else
                    exit(Transaction.Payment);

            if (Transaction."Amount to Account" <> 0) and (Transaction."Amount to Account" < -(Transaction."Gross Amount" + Transaction."Income/Exp. Amount")) then begin
                if COPrepaymentInvoiceMan.IsCustomerOrderPrepaymentInvoiceMarked(Transaction."Customer Order ID") then begin
                    exit(Transaction.Payment - Transaction."Amount to Account")
                end else
                    exit(TotalPayment - Transaction."Amount to Account");
            end;

            if (Transaction."Amount to Account" <> 0) and (Transaction."Amount to Account" = -(Transaction."Gross Amount" + Transaction."Income/Exp. Amount")) then begin
                exit(0);
            end;

            if (Transaction."Amount to Account" > -Transaction."Income/Exp. Amount") then
                exit(-Transaction."Income/Exp. Amount");

            if Transaction."Gross Amount" = 0 then begin
                AmountToDeposit := -Transaction."Amount to Account";
                exit(TotalPayment);
            end;

            if (Transaction."Gross Amount" < 0) and (Transaction.Payment + Transaction."Gross Amount" = Transaction."Amount to Account") then begin
                AmountToDeposit := Transaction."Income/Exp. Amount";
                exit(TotalPayment);
            end;

            if (Transaction."Gross Amount" < 0) and (Transaction.Payment + Transaction."Gross Amount" = -Transaction."Amount to Account") then begin
                exit(-Transaction."Income/Exp. Amount");
            end;

            if (Transaction."Gross Amount" > 0) and (Transaction.Payment + Transaction."Gross Amount" = -Transaction."Income/Exp. Amount") then begin
                exit(TotalPayment);
            end;

            exit(TotalPayment + Transaction."Income/Exp. Amount");
        end;
        //!!!
        if COPrepaymentInvoiceMan.IsCustomerOrderPrepaymentInvoiceMarked(Transaction."Customer Order ID") then begin
            if Transaction."Income/Exp. Amount" > 0 then
                exit(Transaction.Payment - Transaction."Amount to Account");
        end;


        if (Transaction."Amount to Account" > 0) and (Transaction."Amount to Account" = -(Transaction."Gross Amount" + Transaction."Income/Exp. Amount")) then begin
            exit(0);
        end;

        if (Transaction."Amount to Account" > 0) and (Transaction."Amount to Account" < -(Transaction."Gross Amount" + Transaction."Income/Exp. Amount")) then begin
            if Transaction."Customer Order ID" <> '' then begin
                exit(TotalPayment - Transaction."Amount to Account");
            end else begin
                exit(TotalPayment);
            end;
        end;

        if (Transaction."Gross Amount" < 0) and (Transaction.Payment + Transaction."Gross Amount" = -Transaction."Income/Exp. Amount") then
            exit(TotalPayment);

        if Transaction."Amount to Account" < 0 then begin
            AmountToDeposit := -Transaction."Amount to Account";
            exit(TotalPayment);
        end;

        exit(TotalPayment);
    end;

    local procedure PostCustomerOrderPayment(SellToCustNo: Code[20]; TotalAmountPaid: Decimal; AmountToDeposit: Decimal)
    begin
        if Transaction."Amount to Account" <> 0 then
            if AmountToDeposit <> 0 then
                PostPaymentToCustomer(Transaction."Customer Order ID", SellToCustNo, AmountToDeposit,
                    FindSalesOrderPrepaymentInv(Transaction."Customer Order ID"))
            else
                PostPaymentToCustomer(Transaction."Customer Order ID", SellToCustNo, -TotalAmountPaid,
                    FindSalesOrderPrepaymentInv(Transaction."Customer Order ID"));
    end;

    local procedure SetAmountToPost(var GenJournlDocumentType: Enum "Gen. Journal Document Type"; var AmountToPost: Decimal; var SkipCLEPosting: Boolean)
    var
        PostTransactionAsShipment: Boolean;
    begin
        AmountToPost := 0;
        GenJournlDocumentType := GenJournlDocumentType::" ";
        SkipCLEPosting := false;

        PostTransactionAsShipment := Transaction."Post as Shipment";
        OnBeforeCheckPostTransactionAsShipment(Transaction, PostTransactionAsShipment);

        if PostTransactionAsShipment and not Transaction."Customer Order" then
            HandlePostAsShipment(AmountToPost)
        else
            if Transaction."Customer Order ID" <> '' then
                HandleCustomerOrder(GenJournlDocumentType, AmountToPost, SkipCLEPosting)
            else
                HandleGeneralTransaction(GenJournlDocumentType, AmountToPost, SkipCLEPosting);
    end;

    local procedure HandlePostAsShipment(var AmountToPost: Decimal)
    begin
        if CustomerRec."LSC Incl. Inc/Exp on Sales Doc" then
            AmountToPost := 0
        else
            AmountToPost := Transaction."Income/Exp. Amount";
    end;

    local procedure HandleCustomerOrder(var GenJournlDocumentType: Enum "Gen. Journal Document Type"; var AmountToPost: Decimal; var SkipCLEPosting: Boolean)
    begin
        if Transaction.Payment < 0 then
            HandleNegativePaymentForCustomerOrder(GenJournlDocumentType, AmountToPost)
        else
            if Transaction.Payment = 0 then
                HandleZeroPaymentForCustomerOrder(AmountToPost, SkipCLEPosting)
            else
                HandlePositivePaymentForCustomerOrder(AmountToPost, SkipCLEPosting);
    end;

    local procedure HandleNegativePaymentForCustomerOrder(var GenJournlDocumentType: Enum "Gen. Journal Document Type"; var AmountToPost: Decimal)
    begin
        //!!!
        if COPrepaymentInvoiceMan.IsCustomerOrderPrepaymentInvoiceMarked(Transaction."Customer Order ID") then begin
            SkipCLEPosting := true; // the posting to Customer will go thru Business Central Prepayment invoice
            exit;
        end;


        if Transaction.Payment = Transaction."Amount to Account" then begin
            AmountToPost := -Transaction."Amount to Account";
            SkipCLEPosting := true;
            exit;
        end;

        if Transaction."Gross Amount" < 0 then begin
            if Transaction."Income/Exp. Amount" + Transaction."Gross Amount" + Transaction.Payment > 0 then begin
                AmountToPost := Transaction."Income/Exp. Amount";
                exit;
            end;

            if Transaction."Income/Exp. Amount" + Transaction."Gross Amount" + Transaction.Payment = 0 then begin
                AmountToPost := -Transaction.Payment;
                exit;
            end;

            GenJournlDocumentType := GenJournlDocumentType::Payment;
            AmountToPost := 0;
            exit;
        end;

        AmountToPost := -Transaction.Payment;
    end;

    local procedure HandleZeroPaymentForCustomerOrder(var AmountToPost: Decimal; var SkipCLEPosting: Boolean)
    begin
        //!!!
        if (Transaction."Gross Amount" < 0) and (Transaction."Gross Amount" = -Transaction."Income/Exp. Amount") then begin
            if COPrepaymentInvoiceMan.IsCustomerOrderPrepaymentInvoiceMarked(Transaction."Customer Order ID") then begin
                AmountToPost := Transaction."Income/Exp. Amount";
                exit;
            end else begin
                AmountToPost := 0;
                SkipCLEPosting := true;
                exit;
            end;
        end;

        if Transaction."Gross Amount" + Transaction."Income/Exp. Amount" = 0 then begin
            AmountToPost := 0;
            SkipCLEPosting := true;
            exit;
        end;

        AmountToPost := 0;
    end;

    local procedure HandlePositivePaymentForCustomerOrder(var AmountToPost: Decimal; var SkipCLEPosting: Boolean)
    begin
        //!!!
        if COPrepaymentInvoiceMan.IsCustomerOrderPrepaymentInvoiceMarked(Transaction."Customer Order ID") then begin
            AmountToPost := Transaction."Gross Amount";
            exit;
        end;


        if (Transaction."Gross Amount" = 0) and (Transaction.Payment = -Transaction."Income/Exp. Amount") then begin
            if CollectionBySalesOrder(Transaction."Customer Order ID") then begin
                AmountToPost := Transaction."Income/Exp. Amount";
                exit;
            end else begin
                AmountToPost := Transaction."Income/Exp. Amount";
                exit;
            end;
        end;

        if (Transaction."Gross Amount" = 0) and (Transaction."Income/Exp. Amount" < 0) and (Transaction."Amount to Account" = 0) then begin
            AmountToPost := Transaction."Income/Exp. Amount";
            exit;
        end;

        if (Transaction."Gross Amount" = 0) and (Transaction."Income/Exp. Amount" < 0) and (Transaction."Amount to Account" > 0) then begin
            AmountToPost := Transaction."Income/Exp. Amount";
            exit;
        end;

        if (Transaction."Gross Amount" < 0) and (Transaction.Payment + Transaction."Gross Amount" = Transaction."Amount to Account") then begin
            AmountToPost := Transaction."Gross Amount" + Transaction."Income/Exp. Amount";
            exit;
        end;

        if (Transaction."Amount to Account" <> 0) and (Transaction."Amount to Account" < -(Transaction."Gross Amount" + Transaction."Income/Exp. Amount")) then begin
            AmountToPost := Transaction."Gross Amount" + Transaction."Income/Exp. Amount";
            exit;
        end;

        if (Transaction."Amount to Account" <> 0) and (Transaction."Amount to Account" = -(Transaction."Gross Amount" + Transaction."Income/Exp. Amount")) then begin
            AmountToPost := Transaction."Gross Amount" + Transaction."Income/Exp. Amount";
            exit;
        end;

        if (Transaction."Amount to Account" <> 0) and (Transaction."Amount to Account" + Transaction."Income/Exp. Amount" <> 0) then begin
            AmountToPost := -Transaction."Amount to Account";
            exit;
        end;

        if Transaction."Amount to Account" + Transaction."Income/Exp. Amount" = 0 then begin
            SkipCLEPosting := true;
            exit;
        end;

        if CollectionBySalesOrder(Transaction."Customer Order ID") then begin
            if (Transaction."Amount to Account" <> 0) and (Transaction."Amount to Account" < -(Transaction."Gross Amount" + Transaction."Income/Exp. Amount")) then begin
                AmountToPost := Transaction."Gross Amount" + Transaction."Income/Exp. Amount";
                exit;
            end;

            if (Transaction."Amount to Account" <> 0) and (Transaction."Amount to Account" = -(Transaction."Gross Amount" + Transaction."Income/Exp. Amount")) then begin
                AmountToPost := Transaction."Gross Amount" + Transaction."Income/Exp. Amount";
                exit;
            end;
            if (Transaction."Gross Amount" = 0) and (Transaction.Payment = -Transaction."Income/Exp. Amount") then begin
                AmountToPost := Transaction."Income/Exp. Amount";
                exit;
            end;

            if (Transaction."Gross Amount" < 0) and (Transaction.Payment = -(Transaction."Gross Amount" + Transaction."Income/Exp. Amount")) then begin
                AmountToPost := -Transaction.Payment;
                exit;
            end;

            if (Transaction."Gross Amount" > 0) and (Transaction.Payment = -(Transaction."Gross Amount" + Transaction."Income/Exp. Amount")) then begin
                AmountToPost := -Transaction.Payment;
                exit;
            end;

            AmountToPost := Transaction."Gross Amount";
            exit;
        end;

        if (Transaction."Gross Amount" < 0) and (Transaction.Payment + Transaction."Gross Amount" = -Transaction."Income/Exp. Amount") then begin
            AmountToPost := -Transaction.Payment;
            exit;
        end;

        AmountToPost := Transaction."Gross Amount" + Transaction."Income/Exp. Amount";
    end;

    local procedure HandleGeneralTransaction(var GenJournlDocumentType: Enum "Gen. Journal Document Type"; var AmountToPost: Decimal; var SkipCLEPosting: Boolean)
    begin
        if Transaction.Payment < 0 then
            HandleNegativePayment(AmountToPost)
        else
            HandlePositivePayment(GenJournlDocumentType, AmountToPost, SkipCLEPosting);
    end;

    local procedure HandleNegativePayment(var AmountToPost: Decimal)
    begin
        if Transaction."Amount to Account" < 0 then
            if Transaction."Sale Is Return Sale" then
                AmountToPost := Transaction."Gross Amount" - Transaction.Rounded + Transaction."Income/Exp. Amount"
            else
                AmountToPost := -Transaction."Amount to Account"
        else
            AmountToPost := -Transaction.Payment;
    end;

    local procedure HandlePositivePayment(var GenJournlDocumentType: Enum "Gen. Journal Document Type"; var AmountToPost: Decimal; var SkipCLEPosting: Boolean)
    begin
        if Transaction."Transaction Type" = Transaction."Transaction Type"::Payment then
            if Transaction."Amount to Account" < 0 then begin
                AmountToPost := 0;
                SkipCLEPosting := false;
                GenJournlDocumentType := GenJournlDocumentType::Payment;
                exit;
            end;

        if Transaction."Amount to Account" < 0 then begin
            if Transaction.Payment > 0 then begin
                AmountToPost := -Transaction."Amount to Account";
                SkipCLEPosting := true;
            end else
                AmountToPost := 0;
            GenJournlDocumentType := GenJournlDocumentType::Payment;
        end else
            AmountToPost := Transaction."Gross Amount" - Transaction.Rounded + Transaction."Income/Exp. Amount";
    end;

    local procedure CollectionBySalesOrder(CustomerOrderId: Code[20]): Boolean
    var
        CustomerOrderHeader: Record "LSC Customer Order Header";
        PostedCustomerOrderHeader: Record "LSC Posted CO Header";
    begin
        if CustomerOrderId = '' then
            exit(false);
        if CustomerOrderHeader.Get(CustomerOrderId) then begin
            CustomerOrderHeader.Calcfields("Sales Orders");
            if CustomerOrderHeader."Sales Orders" <> 0 then
                exit(true);
        end;
        if PostedCustomerOrderHeader.Get(CustomerOrderId) then begin
            PostedCustomerOrderHeader.Calcfields("Sales Orders", "SO Posted Invoices");
            if (PostedCustomerOrderHeader."Sales Orders" + PostedCustomerOrderHeader."SO Posted Invoices") <> 0 then
                exit(true);
        end;
        exit(false);
    end;

    local procedure TempBlockUnBlockCustomer(CustomerBlocked: enum "Customer Blocked")
    begin
        // Blocks / Unblocks depending on the Customer Blocked enum.
        CustomerRec.Get(CustomerRec."No.");
        CustomerRec.Blocked := CustomerBlocked;
        CustomerRec.Modify();
    end;

    local procedure CreateAndPostToCustomer(DocNumber: Code[20]; GenJournlDocumentType: Enum "Gen. Journal Document Type")
    var
        SellToCustNo: Code[20];
        IsHandled: Boolean;
        Text042: Label 'Slip ';
    begin
        OnBeforePostToCustomer(Statement, Transaction, IsHandled);
        if IsHandled then
            exit;
        //!!!
        if COPrepaymentInvoiceMan.IsCustomerOrderPrepaymentInvoiceMarked(Transaction."Customer Order ID") then
            if AmountToPost = 0 then
                exit;

        if (Transaction.Payment = 0) and (Transaction."Gross Amount" = 0) and (Transaction."Income/Exp. Amount" = 0) then begin
            IsHandled := false;
            OnBeforeCLESkip(AmountToPost, IsHandled);
            if not IsHandled and (AmountToPost = 0) then
                exit;
        end;

        if GenJournlDocumentType <> GenJournlDocumentType::" " then
            DocType := GenJournlDocumentType
        else
            if (AmountToPost > 0) or Transaction."Sale Is Return Sale" then
                if (AmountToPost < 0) and Transaction."Sale Is Return Sale" then
                    DocType := GenJnlLine."Document Type"::Invoice
                else begin
                    DocType := GenJnlLine."Document Type"::"Credit Memo";
                    AmountToPost := -1 * AmountToPost;
                end
            else
                DocType := GenJnlLine."Document Type"::Invoice;

        SellToCustNo := CustomerRec."No.";

        GenJnlLine.Init();
        GenJnlLine."Posting Date" := Statement."Posting Date";
        GenJnlLine."Document Date" := Transaction.Date;
        GenJnlLine."Reason Code" := '';
        GenJnlLine."Document Type" := DocType;
        GenJnlLine."External Document No." := Statement."Posting No.";
        GenJnlLine."LSC Statement No." := Statement."Posting No.";
        GenJnlLine."Account Type" := GenJnlLine."Account Type"::Customer;
        GenJnlLine.Validate("Account No.", CustomerRec."No.");
        GenJnlLine.Description := Text042 + Transaction."Receipt No.";
        GenJnlLine."Document No." := DocNumber;
        if GenJnlLine."Document Type" = Enum::"Gen. Journal Document Type"::"Credit Memo" then
            GenJnlLine.Amount := AmountToPost
        else
            GenJnlLine.Amount := -1 * AmountToPost;
        GenJnlLine.Validate("Currency Code", Transaction."Trans. Currency");
        if Transaction."Trans. Currency" <> '' then begin
            Currency.Get(Transaction."Trans. Currency");
            CurrencyFactor := CurrencyExchRate.ExchangeRate(GenJnlLine."Posting Date", Transaction."Trans. Currency");
            GenJnlLine.Amount := Round(GenJnlLine.Amount, Currency."Amount Rounding Precision");
            GenJnlLine."Sales/Purch. (LCY)" := -1 *
              Round(CurrencyExchRate.ExchangeAmtFCYToLCY(
                Statement."Posting Date", GenJnlLine."Currency Code", Transaction."Net Amount", CurrencyFactor));
            GenJnlLine."Profit (LCY)" := -1 *
              Round(CurrencyExchRate.ExchangeAmtFCYToLCY(
                Statement."Posting Date", GenJnlLine."Currency Code", Transaction."Net Amount" - Transaction."Cost Amount", CurrencyFactor));
        end else begin
            GenJnlLine."Sales/Purch. (LCY)" := -1 * Round(Transaction."Net Amount", GenLedgerSetup."Inv. Rounding Precision (LCY)");
            GenJnlLine."Profit (LCY)" :=
              -1 * Round(Transaction."Net Amount" - Transaction."Cost Amount", GenLedgerSetup."Inv. Rounding Precision (LCY)");
        end;
        if GenJnlLine.Amount = 0 then begin
            GenJnlLine."Sales/Purch. (LCY)" := 0;
            GenJnlLine."Profit (LCY)" := 0;
        end;
        GenJnlLine."Bill-to/Pay-to No." := SellToCustNo;
        GenJnlLine."System-Created Entry" := true;
        GenJnlLine."Source Type" := GenJnlLine."Source Type"::Customer;
        GenJnlLine."Source No." := CustomerRec."No.";
        GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
        GenJnlLine."Salespers./Purch. Code" := '';
        GenJnlLine."Payment Discount %" := 0;
        GenJnlLine."LSC Sell-to Contact No." := Transaction."Sell-to Contact No.";
        GenJnlLine.Validate("VAT Reporting Date", Statement."VAT Reporting Date");
        GenJnlLine."LSC Customer Order No." := Transaction."Customer Order ID";

        CreateGenJnlLineDim(
          GenJnlLine,
          DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
          DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
          Database::"LSC Store", Store."No.",
          Database::Customer, CustomerRec."No.", 0, '', Transaction."Sales Type");
        OnBeforeGenJnlPostLine(GenJnlLine, Statement, Transaction);
        GenJnlPostLine.SetPreviewMode(PreviewMode);
        GenJnlPostLine.RunWithCheck(GenJnlLine);
        TotalSum := TotalSum + GenJnlLine."Amount (LCY)";

        OnAfterPostToCustomer(Statement, Transaction);
    end;

    internal procedure PostNegAdjustment(DocNumber: Code[20])
    var
        SalesType2: Record "LSC Sales Type";
        LocCode: Code[10];
    begin
        GetItem(TransInventoryEntry."Item No.", TransInventoryEntry, Item);

        Clear(TableID);
        Clear(No);
        Clear(ItemPostingBuffer[1]);
        ItemPostingBuffer[1].Type := ItemPostingBuffer[1].Type::NegAdjust;
        ItemPostingBuffer[1]."Serial No." := TransInventoryEntry."Serial No.";
        ItemPostingBuffer[1]."Lot No." := TransInventoryEntry."Lot No.";
        ItemPostingBuffer[1]."Expiration Date" := TransInventoryEntry."Expiration Date";
        ItemPostingBuffer[1]."Item No." := TransInventoryEntry."Item No.";

        LocCode := Store."Location Code";
        if TransInventoryEntry."Sales Type" <> '' then
            if SalesType2.Get(TransInventoryEntry."Sales Type") then
                if SalesType2."Location Code" <> '' then
                    LocCode := SalesType2."Location Code";

        ItemPostingBuffer[1]."Location Code" := LocCode;
        ItemPostingBuffer[1]."Document No." := DocNumber;
        ItemPostingBuffer[1].Quantity := TransInventoryEntry.Quantity;
        ItemPostingBuffer[1]."Source No." := TransInventoryEntry."Variant Code";
        if TransInventoryEntry."Variant Code" <> '' then
            ItemPostingBuffer[1]."Source No." := TransInventoryEntry."Variant Code";
        if BackOfficeSetup."Item Posting Date" = "LSC Item Posting Date"::"Transaction Date" then
            ItemPostingBuffer[1].Date := TransInventoryEntry.Date
        else
            ItemPostingBuffer[1].Date := Statement."Posting Date";
        ItemPostingBuffer[1]."Gen. Prod. Posting Group" := Item."Gen. Prod. Posting Group";
        OnBeforeUpdateItemPostingBufferV2(ItemPostingBuffer[1]);
        OnBeforePostNegAdjV2(ItemPostingBuffer[1], TransInventoryEntry, Transaction);

        Item.CalcFields("Assembly BOM");
        if (Item."Assembly BOM") then begin
            if (Item."LSC Upd Cost and Weight w/Post") then begin
                if BackOfficeSetup."Item Posting Date" = "LSC Item Posting Date"::"Transaction Date" then
                    BOMItemBuffer.Date := TransInventoryEntry.Date
                else
                    BOMItemBuffer.Date := Statement."Posting Date";
                if NOT BOMItemBuffer.Get('', '', TransInventoryEntry."Item No.", '', BOMItemBuffer.Date, FALSE) then begin
                    BOMItemBuffer.Init();
                    BOMItemBuffer."Item No." := TransInventoryEntry."Item No.";
                    if BackOfficeSetup."Item Posting Date" = "LSC Item Posting Date"::"Transaction Date" then
                        BOMItemBuffer.Date := TransInventoryEntry.Date
                    else
                        BOMItemBuffer.Date := Statement."Posting Date";
                    BOMItemBuffer.Insert();
                end;
            end;
            if (Item."LSC Explode BOM in Statem Post") or (Item."LSC Recipe Item Type" = Item."LSC Recipe Item Type"::Recipe) then begin
                BOMPostingBuffer[1]."Document No." := DocNumber;
                if Transaction."To Account" then
                    BOMPostingBuffer[1]."Customer No." := CustomerRec."No.";
                BOMPostingBuffer[1]."Item No." := TransInventoryEntry."Item No.";
                BOMPostingBuffer[1].Quantity := -TransInventoryEntry.Quantity;
                BOMPostingBuffer[1]."Neg. Qty" := BOMPostingBuffer[1].Quantity <= 0;
                BOMPostingBuffer[1]."Location Code" := LocCode;
                BOMPostingBuffer[1]."Serial No." := '';
                BOMPostingBuffer[1]."Lot No." := '';
                BOMPostingBuffer[1]."Expiration Date" := 0D;
                BOMPostingBuffer[1]."Variant Code" := TransInventoryEntry."Variant Code";

                BOMPostingBuffer[1]."Sales Type" := Transaction."Sales Type";
                if (TransInventoryEntry."Sales Type" <> '') then
                    BOMPostingBuffer[1]."Sales Type" := TransInventoryEntry."Sales Type";

                if BackOfficeSetup."Item Posting Date" = "LSC Item Posting Date"::"Transaction Date" then
                    BOMPostingBuffer[1].Date := TransInventoryEntry.Date
                else
                    BOMPostingBuffer[1].Date := Statement."Posting Date";
                UpdBOMPostingBuffer();
            end;
        end;

        UpdItemPostingBuffer();
    end;

    procedure UpdPostingBuffer()
    var
    begin
        OnBeforeUpdLedgerPostingBuffer(PostingBuffer[1], Statement, Transaction, GenJnlLine, TempDimBufNew, TableID, No, Currency);

        PostingBuffer[2] := PostingBuffer[1];
        if PostingBuffer[2].Find() then begin
            if PostingBuffer[2]."Reverse VAT" <> PostingBuffer[1]."Reverse VAT" then begin
                PostingBuffer[1].Insert();
                exit;
            end;

            PostingBuffer[2].Amount := PostingBuffer[2].Amount + PostingBuffer[1].Amount;
            PostingBuffer[2]."VAT Amount" := PostingBuffer[2]."VAT Amount" + PostingBuffer[1]."VAT Amount";

            PostingBuffer[2]."InfoCode Discount Amount" :=
              PostingBuffer[2]."InfoCode Discount Amount" + PostingBuffer[1]."InfoCode Discount Amount";
            if PostingBuffer[1]."InfoCode Discount Account" <> '' then
                PostingBuffer[2]."InfoCode Discount Account" := PostingBuffer[1]."InfoCode Discount Account";

            PostingBuffer[2]."Cust. Discount Amount" :=
              PostingBuffer[2]."Cust. Discount Amount" + PostingBuffer[1]."Cust. Discount Amount";
            if PostingBuffer[1]."Cust. Discount Account" <> '' then
                PostingBuffer[2]."Cust. Discount Account" := PostingBuffer[1]."Cust. Discount Account";

            PostingBuffer[2]."POS Line Disc. Amount" :=
              PostingBuffer[2]."POS Line Disc. Amount" + PostingBuffer[1]."POS Line Disc. Amount";
            if PostingBuffer[1]."POS Line Disc. Account" <> '' then
                PostingBuffer[2]."POS Line Disc. Account" := PostingBuffer[1]."POS Line Disc. Account";

            PostingBuffer[2]."POS Inv. Disc. Amount" :=
              PostingBuffer[2]."POS Inv. Disc. Amount" + PostingBuffer[1]."POS Inv. Disc. Amount";
            if PostingBuffer[1]."POS Inv. Disc. Account" <> '' then
                PostingBuffer[2]."POS Inv. Disc. Account" := PostingBuffer[1]."POS Inv. Disc. Account";

            PostingBuffer[2]."Periodic Disc. Amount" :=
              PostingBuffer[2]."Periodic Disc. Amount" + PostingBuffer[1]."Periodic Disc. Amount";
            if PostingBuffer[1]."Periodic Disc. Account" <> '' then
                PostingBuffer[2]."Periodic Disc. Account" := PostingBuffer[1]."Periodic Disc. Account";

            PostingBuffer[2]."VAT Base Amount" :=
              PostingBuffer[2]."VAT Base Amount" + PostingBuffer[1]."VAT Base Amount";
            if PostingBuffer[2].Amount = 0 then
                PostingBuffer[2].Delete()
            else
                if PostingBuffer[2].Amount = 0 then
                    PostingBuffer[2].Delete()
                else
                    PostingBuffer[2].Modify();
        end else
            PostingBuffer[1].Insert();
    end;

    internal procedure UpdItemPostingBuffer()
    var
        DiscBuffer: Record "LSC Discount Ledger Entry" temporary;
        NextEntryNo: Integer;
    begin
        ItemPostingBuffer[2] := ItemPostingBuffer[1];
        if ItemPostingBuffer[2].Find() then begin
            SumItemPostingBuffer(2);
            DiscLedgerMgt.GetCurrDiscBuffer(DiscBuffer);
            DiscLedgerMgt.UpdateDiscBuffer(ItemPostingBuffer[2]."Discount Entry No.", DiscBuffer);
        end else begin
            NextEntryNo := DiscLedgerMgt.GetNextEntryNo();
            ItemPostingBuffer[1]."Discount Entry No." := NextEntryNo;
            ItemPostingBuffer[1].Insert();
            DiscLedgerMgt.GetCurrDiscBuffer(DiscBuffer);
            DiscLedgerMgt.UpdateDiscBuffer(ItemPostingBuffer[1]."Discount Entry No.", DiscBuffer);
        end;
    end;

    internal procedure SumItemPostingBuffer(SumToIndex: Integer)
    begin
        ItemPostingBuffer[SumToIndex].Quantity := ItemPostingBuffer[2].Quantity +
          ItemPostingBuffer[1].Quantity;
        ItemPostingBuffer[SumToIndex].Amount := ItemPostingBuffer[2].Amount +
          ItemPostingBuffer[1].Amount;
        ItemPostingBuffer[SumToIndex]."Cost Amount" := ItemPostingBuffer[2]."Cost Amount" +
          ItemPostingBuffer[1]."Cost Amount";
        ItemPostingBuffer[SumToIndex]."Line Discount Amount" := ItemPostingBuffer[2]."Line Discount Amount" +
          ItemPostingBuffer[1]."Line Discount Amount";
        ItemPostingBuffer[SumToIndex]."Inv. Discount Amount" := ItemPostingBuffer[2]."Inv. Discount Amount" +
          ItemPostingBuffer[1]."Inv. Discount Amount";

        OnBeforeItemPostingBufferModifyInSumItemPostingBufferV2(SumToIndex, ItemPostingBuffer, Statement);
        ItemPostingBuffer[SumToIndex].Modify();
    end;

    procedure CreateGenJnlLineDim(var GenJnlLine: Record "Gen. Journal Line"; Type1: Integer; No1: Code[20]; Type2: Integer; No2: Code[20]; Type3: Integer; No3: Code[20]; Type4: Integer; No4: Code[20]; Type5: Integer; No5: Code[20]; pSalesType: Code[20])
    var
        CodeDictionary_l: Dictionary of [Integer, Code[20]];
        DimSource_l: List of [Dictionary of [Integer, Code[20]]];
    begin
        TableID[1] := Type1;
        No[1] := No1;
        TableID[2] := Type2;
        No[2] := No2;
        TableID[3] := Type3;
        No[3] := No3;
        TableID[4] := Type4;
        No[4] := No4;
        TableID[5] := Type5;
        No[5] := No5;

        CodeDictionary_l.Add(Type1, No1);
        AddToDimList(CodeDictionary_l, DimSource_l);

        CodeDictionary_l.Add(Type2, No2);
        AddToDimList(CodeDictionary_l, DimSource_l);

        CodeDictionary_l.Add(Type3, No3);
        AddToDimList(CodeDictionary_l, DimSource_l);

        CodeDictionary_l.Add(Type4, No4);
        AddToDimList(CodeDictionary_l, DimSource_l);

        GenJnlLine."Shortcut Dimension 1 Code" := '';
        GenJnlLine."Shortcut Dimension 2 Code" := '';

        if pSalesType <> '' then
            CodeDictionary_l.Add(Database::"LSC Sales Type", pSalesType)
        else
            CodeDictionary_l.Add(Type5, No5);
        AddToDimList(CodeDictionary_l, DimSource_l);

        GenJnlLine."Dimension Set ID" :=
            DimMgt.GetDefaultDimID(DimSource_l, GenJnlLine."Source Code", GenJnlLine."Shortcut Dimension 1 Code", GenJnlLine."Shortcut Dimension 2 Code", 0, 0);

        OnAfterCreateGenJnlLineDim(GenJnlLine, pSalesType, Transaction, TransSalesEntry);
    end;

    local procedure AddToDimList(var CodeDictionary_p: Dictionary of [Integer, Code[20]]; var DimSource_p: List of [Dictionary of [Integer, Code[20]]])
    begin
        DimSource_p.Add(CodeDictionary_p);
        Clear(CodeDictionary_p);
    end;

    procedure CreateItemJnlLineDim(var ItemJnlLine: Record "Item Journal Line"; pDimSource: List of [Dictionary of [Integer, Code[20]]]; pSalesType: Code[20])
    var
        IsHandled: Boolean;
    begin
        OnBeforeCreateItemJnlLineDim(ItemJnlLine, ItemPostingBuffer[1], TempDimBufPost, IsHandled);
        if IsHandled then
            exit;

        ItemJnlLine."Shortcut Dimension 1 Code" := '';
        ItemJnlLine."Shortcut Dimension 2 Code" := '';
        ItemJnlLine."Dimension Set ID" :=
            DimMgt.GetDefaultDimID(pDimSource, ItemJnlLine."Source Code", ItemJnlLine."Shortcut Dimension 1 Code",
            ItemJnlLine."Shortcut Dimension 2 Code", 0, 0);

        OnAfterCreateItemJnlLineDim(ItemJnlLine, pSalesType, Transaction, TransSalesEntry);
    end;

    internal procedure CreateBOMJnlLineDim(var RetailBOMJnlLine: Record "LSC Retail BOM Journal Line"; Type1: Integer; No1: Code[20]; Type2: Integer; No2: Code[20]; pSalesType: Code[20])
    var
        CodeDictionary_l: Dictionary of [Integer, Code[20]];
        DimSource_l: List of [Dictionary of [Integer, Code[20]]];
    begin
        TableID[1] := Type1;
        No[1] := No1;
        TableID[2] := Type2;
        No[2] := No2;

        CodeDictionary_l.Add(Type1, No1);
        AddToDimList(CodeDictionary_l, DimSource_l);

        CodeDictionary_l.Add(Type2, No2);
        AddToDimList(CodeDictionary_l, DimSource_l);

        RetailBOMJnlLine."Shortcut Dimension 1 Code" := '';
        RetailBOMJnlLine."Shortcut Dimension 2 Code" := '';

        if pSalesType <> '' then begin
            CodeDictionary_l.Add(Database::"LSC Sales Type", pSalesType);
            AddToDimList(CodeDictionary_l, DimSource_l);
        end;

        RetailBOMJnlLine."Dimension Set ID" :=
            DimMgt.GetDefaultDimID(DimSource_l, RetailBOMJnlLine."Source Code", RetailBOMJnlLine."Shortcut Dimension 1 Code", RetailBOMJnlLine."Shortcut Dimension 2 Code", 0, 0);

        OnAfterCreateBOMJnlLineDim(RetailBOMJnlLine, pSalesType, Transaction, TransSalesEntry);
    end;

    procedure GetDefaultDim(TableID: array[10] of Integer; No: array[10] of Code[20]; SourceCode: Code[20]; var GlobalDim1Code: Code[20]; var GlobalDim2Code: Code[20]; Len: Integer)
    var
        DefaultDimPriority1: Record "Default Dimension Priority";
        DefaultDimPriority2: Record "Default Dimension Priority";
        DefaultDim: Record "Default Dimension";
        NoFilter: array[2] of Code[20];
        i: Integer;
        j: Integer;
        IsHandled: Boolean;
    begin
        OnBeforeGetDefaultDim(Statement, TableID, No, GlobalDim1Code, GlobalDim2Code, Len, Transaction, TransSalesEntry, IsHandled);
        if IsHandled then
            exit;
        GetGLSetup();
        TempDimBufNew.Reset();
        TempDimBufNew.DeleteAll();
        NoFilter[2] := '';
        for i := 1 to Len do begin
            if (TableID[i] <> 0) and (No[i] <> '') then begin
                DefaultDim.SetRange("Table ID", TableID[i]);
                NoFilter[1] := No[i];
                for j := 1 to 2 do begin
                    DefaultDim.SetRange("No.", NoFilter[j]);
                    if DefaultDim.FindSet() then begin
                        repeat
                            if DefaultDim."Dimension Value Code" <> '' then begin
                                TempDimBufNew.SetRange("Dimension Code", DefaultDim."Dimension Code");
                                if not TempDimBufNew.FindSet() then begin
                                    TempDimBufNew.Init();
                                    TempDimBufNew."Table ID" := DefaultDim."Table ID";
                                    TempDimBufNew."Entry No." := 0;
                                    TempDimBufNew."Dimension Code" := DefaultDim."Dimension Code";
                                    TempDimBufNew."Dimension Value Code" := DefaultDim."Dimension Value Code";
                                    TempDimBufNew.Insert();
                                end else begin
                                    if DefaultDimPriority1.Get(SourceCode, DefaultDim."Table ID") then begin
                                        if DefaultDimPriority2.Get(SourceCode, TempDimBufNew."Table ID") then begin
                                            if DefaultDimPriority1.Priority < DefaultDimPriority2.Priority then begin
                                                TempDimBufNew.Rename(DefaultDim."Table ID", 0, TempDimBufNew."Dimension Code");
                                                TempDimBufNew."Dimension Value Code" := DefaultDim."Dimension Value Code";
                                                TempDimBufNew.Modify();
                                            end;
                                        end else begin
                                            TempDimBufNew.Rename(DefaultDim."Table ID", 0, TempDimBufNew."Dimension Code");
                                            TempDimBufNew."Dimension Value Code" := DefaultDim."Dimension Value Code";
                                            TempDimBufNew.Modify();
                                        end;
                                    end;
                                end;

                                OnAfterInsertDefaultDimensionBuffer(TempDimBufNew, Transaction, TransSalesEntry);
                                if GLSetupShortcutDimCode[1] = TempDimBufNew."Dimension Code" then
                                    GlobalDim1Code := TempDimBufNew."Dimension Value Code";
                                if GLSetupShortcutDimCode[2] = TempDimBufNew."Dimension Code" then
                                    GlobalDim2Code := TempDimBufNew."Dimension Value Code";
                            end;
                        until DefaultDim.Next() = 0;
                    end;
                end;
            end;
        end;
        TempDimBufNew.Reset();
    end;

    local procedure GetGLSetup()
    var
        GLSetup: Record "General Ledger Setup";
    begin
        if not HasGotGLSetup then begin
            GLSetup.Get();
            GLSetupShortcutDimCode[1] := GLSetup."Shortcut Dimension 1 Code";
            GLSetupShortcutDimCode[2] := GLSetup."Shortcut Dimension 2 Code";
            GLSetupShortcutDimCode[3] := GLSetup."Shortcut Dimension 3 Code";
            GLSetupShortcutDimCode[4] := GLSetup."Shortcut Dimension 4 Code";
            GLSetupShortcutDimCode[5] := GLSetup."Shortcut Dimension 5 Code";
            GLSetupShortcutDimCode[6] := GLSetup."Shortcut Dimension 6 Code";
            GLSetupShortcutDimCode[7] := GLSetup."Shortcut Dimension 7 Code";
            GLSetupShortcutDimCode[8] := GLSetup."Shortcut Dimension 8 Code";
            HasGotGLSetup := true;
        end;
    end;

    procedure InsertDimensions(var DimBuf: Record "Dimension Buffer"): Integer
    var
        NewEntryNo: Integer;
    begin
        if DimBuf.FindSet() then begin
            if TempDimBufPost.FindLast() then
                NewEntryNo := TempDimBufPost."Entry No." + 1
            else
                NewEntryNo := 1;
            InsertDimensionsUsingEntryNo(DimBuf, NewEntryNo);
            exit(NewEntryNo);
        end else
            exit(0);
    end;

    internal procedure InsertDimensionsUsingEntryNo(var DimBuf: Record "Dimension Buffer"; EntryNo: Integer)
    begin
        if DimBuf.FindSet() then
            repeat
                TempDimBufPost.Init();
                TempDimBufPost := DimBuf;
                TempDimBufPost."Entry No." := EntryNo;
                TempDimBufPost.Insert();
                TmpInteger.Number := EntryNo;
                if TmpInteger.Insert() then;
            until DimBuf.Next() = 0;
    end;

    procedure FindDimensions(var DimBuf: Record "Dimension Buffer"): Integer
    var
        Match: Boolean;
        Found: Boolean;
        EndOfDimBuf: Boolean;
        EndOfTempDimBuf: Boolean;
        FinalEndOfTempDimBuf: Boolean;
        IsHandled: Boolean;
    begin
        OnBeforeFindDimensions(Statement, DimBuf, TempDimBufPost, IsHandled);
        If IsHandled then
            exit(0);
        if DimBuf.IsEmpty then
            exit(0);

        TempDimBufPost.Reset();
        if TempDimBufPost.IsEmpty then
            exit(0);

        if TmpInteger.FindSet() then
            repeat
                TempDimBufPost.SetRange("Entry No.", TmpInteger.Number);
                DimBuf.FindSet();
                TempDimBufPost.FindSet();
                repeat
                    Match :=
                        (TempDimBufPost."Dimension Code" = DimBuf."Dimension Code") and
                        (TempDimBufPost."Dimension Value Code" = DimBuf."Dimension Value Code");
                    if Match then begin
                        EndOfTempDimBuf := TempDimBufPost.Next() = 0;
                        EndOfDimBuf := DimBuf.Next() = 0;
                    end;
                until EndOfTempDimBuf or EndOfDimBuf or not Match;

                Found := Match and EndOfDimBuf and EndOfTempDimBuf;
                if Found then
                    exit(TempDimBufPost."Entry No.")
                else begin
                    FinalEndOfTempDimBuf := TmpInteger.Next() = 0;
                end;
            until FinalEndOfTempDimBuf;
        exit(0);
    end;

    procedure GetDimensions(EntryNo: Integer; var DimBuf: Record "Dimension Buffer"): Boolean
    begin
        TempDimBufPost.SetRange("Entry No.", EntryNo);
        if not TempDimBufPost.FindSet() then
            exit(false)
        else
            repeat
                DimBuf.Init();
                DimBuf := TempDimBufPost;
                DimBuf.Insert();
            until TempDimBufPost.Next() = 0;
        exit(true);
    end;

    internal procedure UpdBOMPostingBuffer()
    begin
        BOMPostingBuffer[2] := BOMPostingBuffer[1];
        if BOMPostingBuffer[2].Find() then
            SumBOMPostingBuffer(2)
        else
            BOMPostingBuffer[1].Insert();
    end;

    internal procedure SumBOMPostingBuffer(SumToIndex: Integer)
    begin
        BOMPostingBuffer[SumToIndex].Quantity := BOMPostingBuffer[2].Quantity + BOMPostingBuffer[1].Quantity;
        BOMPostingBuffer[SumToIndex].Modify();
    end;

    internal procedure MakeOrder(var TransDiscountEntryTemp: Record "LSC Trans. Discount Entry" temporary; PostGLEntries: Boolean)
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        SalesShpHdr: Record "Sales Shipment Header";
        BlockedCust: Record Customer;
        Location: Record Location;
        SalesOrderItemBuffer: Record "LSC Item Finder Set" temporary;
        SalesPost: Codeunit "Sales-Post";
        TransactionFreeTextUtils: Codeunit "BMG Transaction FreeText Utils";
        DocumentNo: Code[20];
        SalesTypeCode: Code[20];
        IncExpAmount: Decimal;
        LineNo: Integer;
        ShowCreditLimitWarnings: Integer;
        TempCustUnblocking: Boolean;
        SkipPostSalesHeader: Boolean;
        TempChangeShowCreditLimiitWarning: Boolean;
        SkipLocAndDimsValidation: Boolean;
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeMakeOrderChecks(Statement, Transaction, TransDiscountEntryTemp, PostGLEntries, IsHandled);
        if IsHandled then
            exit;

        if TransSalesEntry.FindFirst() then
            TransSalesEntryStatus.Get(TransSalesEntry."Store No.",
              TransSalesEntry."POS Terminal No.",
              TransSalesEntry."Transaction No.",
              TransSalesEntry."Line No.")
        else begin
            TransIncomeExpenseEntry.Reset();
            TransIncomeExpenseEntry.SetRange("Store No.", Transaction."Store No.");
            TransIncomeExpenseEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
            TransIncomeExpenseEntry.SetRange("Transaction No.", Transaction."Transaction No.");
            if TransIncomeExpenseEntry.IsEmpty or not CustomerRec."LSC Incl. Inc/Exp on Sales Doc" then
                exit;

            if Transaction."Customer Order" and TransSalesEntry.IsEmpty then
                exit;
        end;

        Clear(TransIncomeExpenseEntry);

        OnBeforeMakeOrder(TransSalesEntry, Transaction, Statement);
        if TransSalesEntryStatus.Status = TransSalesEntryStatus.Status::"Items Posted" then begin
            SalesShpHdr.SetCurrentKey("Sell-to Customer No.", "External Document No.");
            SalesShpHdr.SetRange("Sell-to Customer No.", Transaction."Customer No.");
            DocumentNo := CreateDocNo(Transaction."Store No.",
              Transaction."POS Terminal No.",
              Transaction."Transaction No.");
            SalesShpHdr.SetRange("External Document No.", DocumentNo);
            if SalesShpHdr.FindSet() then
                repeat
                    if SalesShpHdr."LSC Statement No." <> '' then begin
                        if glUndoItemPosting then
                            SalesShpHdr."LSC Statement No." := DocumentNo
                        else
                            SalesShpHdr."LSC Statement No." := Statement."Posting No.";
                    end;
                    SalesShpHdr.Modify();
                until SalesShpHdr.Next() = 0;
        end else begin
            TransIncomeExpenseEntry.Reset();
            TransIncomeExpenseEntry.SetRange("Store No.", Transaction."Store No.");
            TransIncomeExpenseEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
            TransIncomeExpenseEntry.SetRange("Transaction No.", Transaction."Transaction No.");

            if TransSalesEntry.FindFirst() or not TransIncomeExpenseEntry.IsEmpty then begin
                if CustomerRec.Blocked <> CustomerRec.Blocked::" " then begin // temporarily unblocked
                    BlockedCust.Blocked := CustomerRec.Blocked;
                    CustomerRec.Blocked := CustomerRec.Blocked::" ";
                    CustomerRec.Modify();
                    TempCustUnblocking := true;
                end;

                TempChangeShowCreditLimiitWarning := false;
                SalesReceivablesSetup.Get();
                if SalesReceivablesSetup."Credit Warnings" <> SalesReceivablesSetup."Credit Warnings"::"No Warning" then begin
                    ShowCreditLimitWarnings := SalesReceivablesSetup."Credit Warnings";
                    SalesReceivablesSetup."Credit Warnings" := SalesReceivablesSetup."Credit Warnings"::"No Warning";
                    TempChangeShowCreditLimiitWarning := true;
                    SalesReceivablesSetup.Modify();
                end;

                SalesHeader.Init();

                OnAfterInitSalesHeader(Transaction, SalesHeader);

                if CustomerRec."LSC Incl. Inc/Exp on Sales Doc" then begin
                    if Transaction.Payment >= 0 then
                        SalesHeader."Document Type" := Enum::"Sales Document Type"::Order
                    else begin
                        SalesHeader."Document Type" := Enum::"Sales Document Type"::"Return Order";
                        Transaction."Sale Is Return Sale" := true;
                    end;
                end else begin
                    if Transaction."Gross Amount" < 0 then
                        SalesHeader."Document Type" := Enum::"Sales Document Type"::Order
                    else begin
                        SalesHeader."Document Type" := Enum::"Sales Document Type"::"Return Order";
                        Transaction."Sale Is Return Sale" := true;
                    end;
                end;

                OnAfterAssignDocumentTypeInMakeOrder(Transaction, SalesHeader);

                if BackOfficeSetup."Item Posting Date" = "LSC Item Posting Date"::"Transaction Date" then
                    SalesHeader.Validate("Posting Date", Transaction.Date)
                else
                    SalesHeader.Validate("Posting Date", Statement."Posting Date");

                IsHandled := false;
                OnBeforeMakeOrderValidateSellToCustomerSalesHeader(SalesHeader, Transaction, IsHandled);
                if not IsHandled then
                    SalesHeader.Validate("Sell-to Customer No.", Transaction."Customer No.");

                if not SalesHeader.Insert(true) then begin
                    DocumentNo := CreateDocNo(Transaction."Store No.",
                      Transaction."POS Terminal No.",
                      Transaction."Transaction No.");
                    SalesHeader.Validate("No.", DocumentNo);
                    SalesHeader.Insert(true);
                end;
                DocumentNo := CreateDocNo(Transaction."Store No.",
                  Transaction."POS Terminal No.",
                  Transaction."Transaction No.");
                SalesHeader."External Document No." := DocumentNo;

                SkipLocAndDimsValidation := false;
                OnBeforeValidateSalesHeaderLocationAndDims(SalesHeader, Store, SkipLocAndDimsValidation);
                if not SkipLocAndDimsValidation then begin
                    SalesHeader.Validate("Location Code", Store."Location Code");
                    SalesHeader.Validate("Shortcut Dimension 1 Code", Store."Global Dimension 1 Code");

                    SalesTypeCode := Transaction."Sales Type";
                    if TransSalesEntry."Sales Type" <> '' then
                        SalesTypeCode := TransSalesEntry."Sales Type";

                    FindSalesType(SalesTypeCode);

                    if SalesTypes."Global Dimension 1 Code" <> '' then
                        SalesHeader.Validate("Shortcut Dimension 1 Code", SalesTypes."Global Dimension 1 Code");

                    if SalesTypes."Global Dimension 2 Code" <> '' then
                        SalesHeader.Validate("Shortcut Dimension 2 Code", SalesTypes."Global Dimension 2 Code")
                    else
                        if Store."Global Dimension 2 Code" <> '' then
                            SalesHeader.Validate("Shortcut Dimension 2 Code", Store."Global Dimension 2 Code");
                end;

                SalesHeader."Prices Including VAT" := true;
                SalesHeader.Invoice := false;

                if Transaction."Sale Is Return Sale" then
                    SalesHeader.Receive := true
                else
                    SalesHeader.Ship := true;

                SalesHeader."LSC Statement No." := Statement."Posting No.";
                if SalesHeader."Currency Code" <> Transaction."Trans. Currency" then
                    SalesHeader.Validate("Currency Code", Transaction."Trans. Currency");

                SalesHeader."LSC Customer Order ID" := Transaction."Customer Order ID";

                OnBeforeModifySalesHeaderInMakeOrder(SalesHeader, Transaction, Statement);
                SalesHeader.Modify();

                TransactionFreeTextUtils.AddTransTextLinesToSalesDocument(Transaction, SalesHeader, 0, 0);

                TransPostingFunctions.ClearItemNoBuffer();
                LineNo := 0;
                if TransSalesEntry.FindSet() then
                    repeat
                        GetItem(TransSalesEntry."Item No.", TransSalesEntry, Item);
                        TransPostingFunctions.SetItemBlockReserve(Item."No.");
                        TransPostingFunctions.SetItemNoInBuffer(Item."No.");
                        Clear(SalesLine);
                        SalesLine."Document Type" := SalesHeader."Document Type";
                        SalesLine."Document No." := SalesHeader."No.";
                        LineNo += 10000;
                        SalesLine."Line No." := LineNo;
                        SalesLine.Insert(true);
                        SalesLine.Type := SalesLine.Type::Item;
                        SalesLine.Validate("No.", TransSalesEntry."Item No.");
                        SalesLine."Item Reference No." := CopyStr(TransSalesEntry."Barcode No.", 1, MaxStrLen(SalesLine."Item Reference No."));
                        SalesLine.Validate("Variant Code", TransSalesEntry."Variant Code");
                        if SalesLine.IsInventoriableItem() then
                            SalesLine.Validate("Location Code", SalesHeader."Location Code");

                        OnMakeOrderBeforeValidateQuantities(SalesLine, SalesHeader, TransSalesEntry);
                        if TransSalesEntry."Unit of Measure" <> '' then
                            SalesLine.Validate("Unit of Measure Code", TransSalesEntry."Unit of Measure")
                        else
                            SalesLine.Validate("Unit of Measure Code", '');

                        if Transaction."Sale Is Return Sale" then
                            TransSalesEntry.Quantity := -TransSalesEntry.Quantity;
                        if TransSalesEntry."UOM Quantity" <> 0 then begin
                            SalesLine.Validate(Quantity, -TransSalesEntry."UOM Quantity");
                            SalesLine.Validate("Unit Price", TransSalesEntry.Price * TransSalesEntry.Quantity / TransSalesEntry."UOM Quantity");
                        end else begin
                            SalesLine.Validate(Quantity, -TransSalesEntry.Quantity);
                            SalesLine.Validate("Unit Price", TransSalesEntry.Price);
                        end;

                        if Transaction."Sale Is Return Sale" then begin
                            TransSalesEntry.Quantity := -TransSalesEntry.Quantity;
                            SalesLine.Validate("Line Discount Amount", -(TransSalesEntry."Discount Amount" - TransSalesEntry."Total Discount"));
                        end else
                            SalesLine.Validate("Line Discount Amount", TransSalesEntry."Discount Amount" - TransSalesEntry."Total Discount");
                        SalesLine.Validate("Inv. Discount Amount", TransSalesEntry."Total Discount");
                        SalesLine."LSC Offer No." := TransSalesEntry."Periodic Disc. Group";
                        SalesLine."LSC Promotion No." := TransSalesEntry."Promotion No.";
                        OnBeforeModifySalesLine(SalesLine, Transaction, TransSalesEntry, TransIncomeExpenseEntry);

                        if TransSalesEntry."Serial No." <> '' then
                            TransPostingFunctions.AddSalesLineSerialNoTracking(SalesHeader, SalesLine, TransSalesEntry."Serial No.", TransSalesEntry."Expiration Date");

                        if TransSalesEntry."Lot No." <> '' then
                            TransPostingFunctions.AddSalesLineLotNoTracking(SalesHeader, SalesLine, TransSalesEntry."Lot No.", TransSalesEntry."Expiration Date");

                        SalesLine.Modify(true);
                        OnAfterSalesLineModify(SalesLine, TransSalesEntry, TransIncomeExpenseEntry);

                        InsertSalesLineDiscEntry(TransDiscountEntryTemp, TransSalesEntry, SalesLine);
                        TransactionFreeTextUtils.AddTransTextLinesToSalesDocument(Transaction, SalesHeader, TransSalesEntry."Line No.", SalesLine."Line No.");
                        TransPostingFunctions.ResetItemBlockReserve();
                    until TransSalesEntry.Next() = 0;

                if SalesHeader."No." <> '' then
                    if CustomerRec."LSC Incl. Inc/Exp on Sales Doc" then begin
                        Clear(TransSalesEntry);
                        TransIncomeExpenseEntry.Reset();
                        TransIncomeExpenseEntry.SetRange("Store No.", Transaction."Store No.");
                        TransIncomeExpenseEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                        TransIncomeExpenseEntry.SetRange("Transaction No.", Transaction."Transaction No.");
                        if TransIncomeExpenseEntry.FindSet() then
                            repeat
                                IncomeExpenseAcc.Get(Store."No.", TransIncomeExpenseEntry."No.");
                                IncomeExpenseAcc.TestField(IncomeExpenseAcc."G/L Account");
                                GLAccount2.Get(IncomeExpenseAcc."G/L Account");

                                Clear(SalesLine);
                                SalesLine."Document Type" := SalesHeader."Document Type";
                                SalesLine."Document No." := SalesHeader."No.";
                                LineNo += 10000;
                                SalesLine."Line No." := LineNo;
                                SalesLine.Insert(true);
                                SalesLine.Type := SalesLine.Type::"G/L Account";
                                SalesLine.Validate("No.", IncomeExpenseAcc."G/L Account");
                                OnMakeOrderBeforeValidateQuantities2(SalesLine, SalesHeader, TransIncomeExpenseEntry);
                                SalesLine.Validate(Quantity, 1);
                                if SalesLine."Document Type" = Enum::"Sales Document Type"::Order then
                                    IncExpAmount := -TransIncomeExpenseEntry.Amount
                                else
                                    IncExpAmount := TransIncomeExpenseEntry.Amount;
                                SalesLine.Validate("Unit Price", IncExpAmount);
                                OnBeforeModifySalesLine(SalesLine, Transaction, TransSalesEntry, TransIncomeExpenseEntry);
                                SalesLine.Modify(true);
                                OnAfterSalesLineModify(SalesLine, TransSalesEntry, TransIncomeExpenseEntry);
                            until TransIncomeExpenseEntry.next() = 0;
                    end;

                SkipPostSalesHeader := false;
                if Transaction."Sale Is Return Sale" then
                    if Location.Get(Store."Location Code") then
                        if Location."Require Receive" then begin
                            if not SkipPostSalesHeader then begin
                                SkipPostSalesHeader := true;
                                ShowReturnOrderMsg := true;
                                FirstReturnOrderNo := SalesHeader."No.";
                            end;
                            LastReturnOrderNo := SalesHeader."No.";
                        end;

                OnBeforeCheckPostSalesHeader(Transaction, SalesHeader, SkipPostSalesHeader, PreviewMode);

                if not SkipPostSalesHeader then begin
                    TransPostingFunctions.GetItemNoBuffer(SalesOrderItemBuffer);
                    SalesOrderItemBuffer.Reset();
                    if SalesOrderItemBuffer.FindSet() then
                        repeat
                            TransPostingFunctions.SetItemBlockReserve(SalesOrderItemBuffer."Item No.");
                        until SalesOrderItemBuffer.Next() = 0;

                    OnBeforePostSalesOrderInMakeOrder(SalesHeader);
                    Clear(SalesPost);
                    SalesPost.SetSuppressCommit(true);
                    SalesPost.SetPreviewMode(PreviewMode);
                    SalesPost.Run(SalesHeader);
                    TransPostingFunctions.ResetItemBlockReserve();
                    TransPostingFunctions.ClearItemNoBuffer();
                end;

                if TempCustUnblocking then begin
                    CustomerRec.Get(CustomerRec."No.");
                    CustomerRec.Blocked := BlockedCust.Blocked;
                    CustomerRec.Modify();
                    TempCustUnblocking := false;
                end;
                if TempChangeShowCreditLimiitWarning then begin
                    SalesReceivablesSetup.Get();
                    SalesReceivablesSetup."Credit Warnings" := ShowCreditLimitWarnings;
                    SalesReceivablesSetup.Modify();
                end;
                OnAfterMakeOrder(SalesHeader, Transaction, Statement);
            end;
        end;
    end;

    internal procedure PostItem()
    var
        RBOtoAdjust: Record "LSC Adj. Item Ledgers for RBO";
        DiscBuffer: Record "LSC Discount Ledger Entry" temporary;
        RetailItemJnlExt: Codeunit "LSC Retail Item Jnl. Ext.";
        CodeDictionary_l: Dictionary of [Integer, Code[20]];
        DimSource_l: List of [Dictionary of [Integer, Code[20]]];
        AdjustedUnitCost: Decimal;
        IsHandled: Boolean;
    begin
        OnBeforeCompressItemPostingBuffer(IsHandled);
        if not IsHandled then
            CompressItemPostingBuffer();
        OnBeforePostItemV2(ItemPostingBuffer[1], Statement);
        ItemPostingBuffer[1].Quantity := Round(ItemPostingBuffer[1].Quantity, 0.00001);

        if ItemPostingBuffer[1].Quantity <> 0 then begin
            GetItem(ItemPostingBuffer[1]."Item No.", ItemPostingBuffer[1], Item);
            if (Format(Item."LSC Lifecycle Length") <> '') and
               (Item."LSC Lifecycle Starting Date" = 0D) then begin
                Item."LSC Lifecycle Starting Date" := Today;
                Item."LSC Lifecycle Ending Date" := CalcDate(Item."LSC Lifecycle Length", Today);
                Item.Modify();
            end;
            TransPostingFunctions.SetItemBlockReserve(Item."No.");
            Clear(ItemJnlLine);
            ItemJnlLine.Init();
            ItemJnlLine."Item No." := ItemPostingBuffer[1]."Item No.";
            ItemJnlLine."Variant Code" := ItemPostingBuffer[1]."Source No.";
            ItemJnlLine."Posting Date" := ItemPostingBuffer[1].Date;
            ItemJnlLine."Document Date" := Statement."Posting Date";
            if Item.Type = Item.Type::Inventory then
                ItemJnlLine.Validate("Entry Type", ItemJnlLine."Entry Type"::Sale)
            else
                ItemJnlLine."Entry Type" := ItemJnlLine."Entry Type"::Sale;
            ItemJnlLine."Document No." := ItemPostingBuffer[1]."Document No.";
            ItemJnlLine."External Document No." := ItemPostingBuffer[1]."Document No.";
            ItemJnlLine."LSC BO Doc. No." := Statement."Posting No.";
            ItemJnlLine.Description := Item.Description;
            ItemJnlLine."Location Code" := ItemPostingBuffer[1]."Location Code";
            ItemJnlLine."Inventory Posting Group" := Item."Inventory Posting Group";
            ItemJnlLine."Source Posting Group" := '';
            if Item."Base Unit of Measure" <> '' then begin
                ItemJnlLine.Validate("Unit of Measure Code", Item."Base Unit of Measure");
                ItemJnlLine.Validate(Quantity, ItemPostingBuffer[1].Quantity);
            end else begin
                ItemJnlLine."Unit of Measure Code" := '';
                ItemJnlLine."Qty. per Unit of Measure" := 1;
                ItemJnlLine.Validate("Quantity (Base)", ItemPostingBuffer[1].Quantity);
            end;
            ItemJnlLine."LSC BO Doc. No." := Statement."Posting No.";
            if Statement."Posting No." = '' then
                ItemJnlLine."LSC BO Doc. No." := Statement."No.";
            ItemJnlLine."Unit Amount" := Round(ItemPostingBuffer[1].Amount / ItemPostingBuffer[1].Quantity);
            ItemJnlLine.Amount := ItemPostingBuffer[1].Amount;
            ItemJnlLine."Discount Amount" := ItemPostingBuffer[1]."Line Discount Amount" + ItemPostingBuffer[1]."Inv. Discount Amount";
            ItemJnlLine."Salespers./Purch. Code" := ItemPostingBuffer[1]."Salesperson Code";
            ItemJnlLine."Source Code" := BackOfficeSetup."Source Code";
            ItemJnlLine."Gen. Bus. Posting Group" := ItemPostingBuffer[1]."Gen. Bus. Posting Group";
            ItemJnlLine."Gen. Prod. Posting Group" := ItemPostingBuffer[1]."Gen. Prod. Posting Group";
            ItemJnlLine."LSC Offer No." := ItemPostingBuffer[1]."Offer No.";
            ItemJnlLine."LSC Promotion No." := ItemPostingBuffer[1]."Promotion No.";

            ItemJnlLine."Expiration Date" := ItemPostingBuffer[1]."Expiration Date";
            if (ItemPostingBuffer[1]."Serial No." <> '') or (ItemPostingBuffer[1]."Lot No." <> '') then
                TransPostingFunctions.AddSerialNoAndLotNoTracking(ItemJnlLine, ItemPostingBuffer[1]."Serial No.", ItemPostingBuffer[1]."Lot No.", ItemPostingBuffer[1]."Expiration Date");

            if ItemPostingBuffer[1]."Customer No." <> '' then begin
                ItemJnlLine."Source No." := ItemPostingBuffer[1]."Customer No.";
                ItemJnlLine."Source Type" := ItemJnlLine."Source Type"::Customer;
            end;

            CodeDictionary_l.Add(Database::Item, ItemJnlLine."Item No.");
            AddToDimList(CodeDictionary_l, DimSource_l);

            CodeDictionary_l.Add(Database::"LSC Store", Store."No.");
            AddToDimList(CodeDictionary_l, DimSource_l);

            if ItemPostingBuffer[1]."Customer No." <> '' then begin
                CodeDictionary_l.Add(Database::Customer, ItemPostingBuffer[1]."Customer No.");
                AddToDimList(CodeDictionary_l, DimSource_l);
            end;

            if ItemPostingBuffer[1]."Salesperson Code" <> '' then begin
                CodeDictionary_l.Add(Database::"Salesperson/Purchaser", ItemPostingBuffer[1]."Salesperson Code");
                AddToDimList(CodeDictionary_l, DimSource_l);
            end;

            if ItemPostingBuffer[1]."Sales Type" <> '' then begin
                CodeDictionary_l.Add(Database::"LSC Sales Type", ItemPostingBuffer[1]."Sales Type");
                AddToDimList(CodeDictionary_l, DimSource_l);
            end;

            CreateItemJnlLineDim(ItemJnlLine, DimSource_l, ItemPostingBuffer[1]."Sales Type");

            DiscLedgerMgt.GetDiscBuffer(ItemPostingBuffer[1]."Discount Entry No.", DiscBuffer);
            RetailItemJnlExt.SetDiscLedgerBuffer(ItemJnlLine, DiscBuffer);
            OnBeforeItemJnlLinePostLineV2(ItemJnlLine, Statement, ItemPostingBuffer[1]);
            if not PreviewMode then
                ItemJnlPostLine.RunWithCheck(ItemJnlLine);
            OnAfterItemJnlLinePostLine(ItemJnlLine, Statement);
            RetailItemJnlExt.ClearDiscLedgerBuffer(ItemJnlLine);
            TransPostingFunctions.ResetItemBlockReserve();
            if BackOfficeSetup."Update Cost Amount" then begin
                if not RBOtoAdjust.FindLast() then
                    RBOtoAdjust."Entry No." := 0;
                RBOtoAdjust.Init();
                RBOtoAdjust."Entry No." += 1;
                RBOtoAdjust."Item Ledger No." := RetailItemJnlExt.GetItemLedgEntryNo();
                RBOtoAdjust."Item No." := ItemJnlLine."Item No.";
                RBOtoAdjust."Adjusted Qty." := -ItemJnlLine.Quantity;
                AdjustedUnitCost := (ItemPostingBuffer[1]."Cost Amount" / ItemPostingBuffer[1].Quantity) - ItemJnlLine."Unit Cost";
                RBOtoAdjust."Adjusted Amount" := AdjustedUnitCost * ItemPostingBuffer[1].Quantity;
                RBOtoAdjust."RBO No." := CopyStr(ItemJnlLine."LSC BO Doc. No.", 1, MaxStrLen(RBOtoAdjust."RBO No."));
                RBOtoAdjust.Date := Today;
                RBOtoAdjust.Time := Time;
                if RBOtoAdjust."Adjusted Amount" <> 0 then
                    RBOtoAdjust.Insert();
            end;
        end;
    end;

    internal procedure PostBOM()
    begin
        if not BOMPostingBuffer[1]."Neg. Qty" then
            if BOMPostingBuffer[2].Get(
              BOMPostingBuffer[1]."Document No.", BOMPostingBuffer[1]."Customer No.",
              BOMPostingBuffer[1]."Item No.", BOMPostingBuffer[1]."Variant Code",
              BOMPostingBuffer[1].Date, true)
            then
                if BOMPostingBuffer[1].Quantity + BOMPostingBuffer[2].Quantity <> 0 then begin
                    SumBOMPostingBuffer(1);
                    BOMPostingBuffer[2].Delete();
                end;

        Clear(RetailBOMJnlLine);
        RetailBOMJnlLine.Init();
        RetailBOMJnlLine.Validate("Item No.", BOMPostingBuffer[1]."Item No.");
        if BOMPostingBuffer[1]."Variant Code" <> '' then
            RetailBOMJnlLine.Validate("Variant Code", BOMPostingBuffer[1]."Variant Code");
        RetailBOMJnlLine.Validate(Quantity, BOMPostingBuffer[1].Quantity);
        RetailBOMJnlLine."Posting Date" := BOMPostingBuffer[1].Date;
        RetailBOMJnlLine."Document No." := BOMPostingBuffer[1]."Document No.";
        RetailBOMJnlLine."Document Date" := Statement."Posting Date";
        RetailBOMJnlLine."Location Code" := BOMPostingBuffer[1]."Location Code";
        RetailBOMJnlLine."Source Code" := BackOfficeSetup."Source Code";
        RetailBOMJnlLine."Statement No." := Statement."Posting No.";
        RetailBOMJnlLine."BO Doc. No." := Statement."Posting No.";
        if Statement."Posting No." = '' then
            RetailBOMJnlLine."BO Doc. No." := Statement."No.";
        OnBeforeRetailBOMJnlPostLine(RetailBOMJnlLine, BOMPostingBuffer[1]);
        PostBOMRecursive(RetailBOMJnlLine);
    end;

    internal procedure PostBOMRecursive(pRetailBOMJnlLine: Record "LSC Retail BOM Journal Line")
    var
        RetailBOMJnlLineRe: Record "LSC Retail BOM Journal Line";
        ItemLoc: Record Item;
        BOMComp: Record "BOM Component";
        UOMMgmt: Codeunit "Unit of Measure Management";
    begin
        BOMComp.Reset();
        BOMComp.SetRange("Parent Item No.", pRetailBOMJnlLine."Item No.");
        BOMComp.SetRange(Type, Enum::"BOM Component Type"::Item);
        BOMComp.SetFilter("No.", '<>%1', '');
        if BOMComp.FindSet() then
            repeat
                ItemLoc.Get(BOMComp."No.");
                ItemLoc.CalcFields("Assembly BOM");
                if (ItemLoc."Assembly BOM") and (ItemLoc."LSC Explode BOM in Statem Post") then begin
                    RetailBOMJnlLineRe := pRetailBOMJnlLine;
                    RetailBOMJnlLineRe.Validate("Item No.", BOMComp."No.");
                    if BOMComp."Variant Code" <> '' then
                        RetailBOMJnlLineRe."Variant Code" := BOMComp."Variant Code";
                    RetailBOMJnlLineRe.Validate(Quantity, pRetailBOMJnlLine.Quantity * BOMComp."Quantity per" * UOMMgmt.GetQtyPerUnitOfMeasure(ItemLoc, BOMComp."Unit of Measure Code"));
                    OnBeforeRetailBOMJnlPostBOMCompLine(RetailBOMJnlLineRe, Store);
                    PostBOMRecursive(RetailBOMJnlLineRe);
                end;
            until BOMComp.Next() = 0;

        CreateBOMJnlLineDim(
          pRetailBOMJnlLine, Database::Item, pRetailBOMJnlLine."Item No.", Database::"LSC Store", Store."No.", BOMPostingBuffer[1]."Sales Type");

        OnBeforeRetailBOMJnlPostLineRunWithCheck(pRetailBOMJnlLine, Statement);
        if not PreviewMode then begin
            //!!!RetailBOMJnlPostLine.SetTransaction(Transaction);
            RetailBOMJnlPostLine.RunWithCheck(pRetailBOMJnlLine);
        end;
    end;

    procedure RunItemPosting(locStatement: Record "LSC Statement"; UndoItemPosting: Boolean)
    var
        ItemPostingBuffer_RV: Record "LSC Item Posting Buffer V2";
        ItemPostingBuffer_Temp: Record "LSC Item Posting Buffer V2";
        TransDiscEntryTemp: Record "LSC Trans. Discount Entry" temporary;
        UpdateAnalysisView: Codeunit "Update Analysis View";
        DocumentNo: Code[20];
        IsHandled: Boolean;
        PostTransactionAsShipment: Boolean;
        Text057: Label 'The %1 sales entries were sucessfully posted';
        Text047: Label 'Item Posting can''t be undone';
    begin
        LockTimeout(false);
        OnBeforeRunItemPosting(Statement, UndoItemPosting, IsHandled, locStatement);
        if IsHandled then
            exit;

        TransPostingFunctions.InitFunction();

        ItemPostingBuffer[1].DeleteAll();
        BOMPostingBuffer[1].DeleteAll();
        ItemAdjustPostBuffer[1].DeleteAll();

        Statement := locStatement;
        glUndoItemPosting := UndoItemPosting;
        Clear(ItemJnlPostLine);

        if UndoItemPosting then
            Error(Text047);

        TransactionStatus.Reset();
        TransactionStatus.SetCurrentKey("Statement No.");
        TransactionStatus.SetRange("Statement No.", Statement."No.");
        if TransactionStatus.IsEmpty then
            Error(Text014);

        if (not UndoItemPosting) and (not locStatement."Skip Confirmation") then
            "Cust/ItemChecks"(Statement, TRUE);

        Store.Get(locStatement."Store No.");
        Store.TestField("Gen. Bus. Post. Gr.");
        BackOfficeSetup.Get();
        CompletePost := false;

        CalculateTransactionDiscounts(TransDiscEntryTemp, Statement."No.");
        OpenTablesBuffers();
        if TransactionStatus.FindSet() then
            repeat
                if TransactionStatus.Status < TransactionStatus.Status::"Items Posted" then begin
                    Transaction.Get(TransactionStatus."Store No.", TransactionStatus."POS Terminal No.", TransactionStatus."Transaction No.");
                    if CheckTransSubTables(Transaction) then begin
                        if Transaction."To Account" then begin
                            if not CustomerRec.Get(Transaction."Customer No.") then
                                Error(
                                    Text031,
                                    Transaction.FieldCaption("Customer No."), Transaction."Customer No.", CustomerRec.TableCaption);
                            TransSalesEntry.SetRange("Store No.", Transaction."Store No.");
                            TransSalesEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                            TransSalesEntry.SetRange("Transaction No.", Transaction."Transaction No.");
                            PostTransactionAsShipment := Transaction."Post as Shipment";
                            OnBeforeCheckPostTransactionAsShipment(Transaction, PostTransactionAsShipment);
                            if PostTransactionAsShipment then
                                MakeOrder(TransDiscEntryTemp, false)
                            else begin
                                if TransSalesEntry.FindSet() then
                                    repeat
                                        DocumentNo := CreateDocNo(TransSalesEntry."Store No.",
                                            TransSalesEntry."POS Terminal No.",
                                            TransSalesEntry."Transaction No.");
                                        PostItemSales(TransDiscEntryTemp, DocumentNo, false);
                                    until TransSalesEntry.Next() = 0;
                            end;
                        end else begin
                            TransSalesEntry.SetRange("Store No.", Transaction."Store No.");
                            TransSalesEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                            TransSalesEntry.SetRange("Transaction No.", Transaction."Transaction No.");
                            if TransSalesEntry.FindSet() then
                                repeat
                                    if locStatement."Posting No." = '' then
                                        PostItemSales(TransDiscEntryTemp, locStatement."No.", false)
                                    else
                                        PostItemSales(TransDiscEntryTemp, locStatement."Posting No.", false);
                                until TransSalesEntry.Next() = 0;
                        end;
                        if not UndoItemPosting then begin
                            TransactionStatus.Status := TransactionStatus.Status::"Items Posted";
                            TransStatusToBuffer(TransactionStatus);
                        end;
                    end;
                end;
            until TransactionStatus.Next() = 0;

        if BOMPostingBuffer[1].FindSet() then
            repeat
                PostBOM();
            until BOMPostingBuffer[1].Next() = 0;

        ItemAdjustPostBuffer[1].Reset();
        if ItemAdjustPostBuffer[1].FindSet() then
            repeat
                PostItemAdjustment();
            until ItemAdjustPostBuffer[1].Next() = 0;
        TransPostingFunctions.InsertInvAdjustEntryV2(ItemAdjustPostBuffer[1]);

        ItemPostingBuffer[1].SetCurrentKey("Item No.", "Location Code", "Department Code", "Source No.", "Serial No.", "Lot No.", Date, "Salesperson Code", "Neg. Qty", "Offer No.", "Promotion No.", "Entry No.");
        ItemPostingBuffer[1].SetAscending("Neg. Qty", false);
        if ItemPostingBuffer[1].FindSet() then
            repeat
                if (ItemPostingBuffer[1]."Serial No." <> '') or (ItemPostingBuffer[1]."Lot No." <> '') then begin
                    CompressItemPostingBuffer();
                    if OkToPostDirect(ItemPostingBuffer[1]) then
                        PostItem
                    else
                        if FindReversePosting(ItemPostingBuffer[1], ItemPostingBuffer_RV) then begin
                            ItemPostingBuffer_Temp := ItemPostingBuffer[1];
                            ItemPostingBuffer[1] := ItemPostingBuffer_RV;
                            PostItem();
                            ItemPostingBuffer[1] := ItemPostingBuffer_Temp;
                            PostItem();
                        end else
                            PostItem();
                    ItemPostingBuffer[1].Delete();
                end else
                    PostItem();
            until ItemPostingBuffer[1].Next() = 0;

        FlushTablesBuffers();

        if not UndoItemPosting then begin
            locStatement.Status := locStatement.Status::"Sales Entries Posted";
            if not CompletePost then
                locStatement.Modify(true)
            else
                locStatement.Modify();
        end;
        Clear(glUndoItemPosting);

        UpdateAnalysisView.UpdateAll(0, true);
        if not RunningFromBatchPosting then
            if not UndoItemPosting then
                Message(Text057, Statement.TableCaption);
        OnAfterRunItemPosting(Statement, UndoItemPosting);
    end;

    procedure "Cust/ItemChecks"(var Statement_p: Record "LSC Statement"; CheckBlockedCustomer: Boolean)
    var
        IsHandled: Boolean;
        Text006: Label 'There are %1 blocked %2 records in the %3 %4 records. \\';
        Text007: Label 'Do you want to temporarily unblock the %2 records until posting is completed?';
    begin
        if Statement_p."No. of Blocked Items" > 0 then begin
            Txt := StrSubstNo(
              Text006 +
              Text007,
              Statement_p."No. of Blocked Items", Item.TableCaption, Statement_p.TableCaption, Transaction.TableCaption);
            if not GuiAllowed then
                Error(Text002)
            else
                if not Confirm(Txt, false) then
                    Error(Text002);
        end;
        OnBeforeCheckBlockedCustOfCustItemChecks(Statement_p, CheckBlockedCustomer, IsHandled);
        if IsHandled then
            exit;

        if Statement_p."No. of Blocked Cust." > 0 then begin
            Txt := StrSubstNo(
              Text006 +
              Text007,
              Statement_p."No. of Blocked Cust.", CustomerRec.TableCaption, Statement_p.TableCaption, Transaction.TableCaption);
            if not GuiAllowed then
                Error(Text002)
            else
                if not Confirm(Txt, false) then
                    Error(Text002);
        end;
    end;

    procedure CheckEmptyTenderType(var StatementLine: Record "LSC Statement Line"; Statement: Record "LSC Statement")
    begin
    end;


    procedure PrePostingChecks(var Stmt_p: Record "LSC Statement"; var Store_p: Record "LSC Store"; RunningFromBatchPosting_p: Boolean);
    var
        StatementPostPreCheck: Codeunit "LSC Statement-Post Pre Checks";
    begin
        //!!!StatementPostPreCheck.PrePostingChecks(Stmt_p, Store_p, RunningFromBatchPosting_p);
    end;

    internal procedure PostPaymentToCustomer(DocNumber: Code[20]; SellToCustNo: Code[20]; TotalAmountPaid: Decimal; AppliesToDocNo: Code[20])
    var
        AppliesToDocType: Enum "Gen. Journal Document Type";
        Text043: Label 'Payment ';
    begin
        GenJnlLine.Init();
        GenJnlLine."Posting Date" := Statement."Posting Date";
        GenJnlLine."Document Date" := Transaction.Date;
        GenJnlLine."Reason Code" := '';
        GenJnlLine."Account Type" := GenJnlLine."Account Type"::Customer;
        GenJnlLine.Validate("Account No.", SellToCustNo);
        GenJnlLine.Description := Text043 + Transaction."Receipt No.";
        if TotalAmountPaid < 0 then
            GenJnlLine."Document Type" := GenJnlLine."Document Type"::Refund
        else
            GenJnlLine."Document Type" := GenJnlLine."Document Type"::Payment;
        GenJnlLine."Document No." := DocNumber;
        GenJnlLine."External Document No." := Statement."Posting No.";
        GenJnlLine."LSC Statement No." := Statement."Posting No.";
        GenJnlLine.Amount := -1 * TotalAmountPaid;
        GenJnlLine.Validate("Currency Code", Transaction."Trans. Currency");
        GenJnlLine.Amount := Round(GenJnlLine.Amount);
        GenJnlLine."Bill-to/Pay-to No." := SellToCustNo;
        GenJnlLine."Source Type" := GenJnlLine."Source Type"::Customer;
        GenJnlLine."Source No." := SellToCustNo;
        GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
        GenJnlLine."Salespers./Purch. Code" := '';
        GenJnlLine."LSC Sell-to Contact No." := Transaction."Sell-to Contact No.";
        GenJnlLine."LSC Customer Order No." := Transaction."Customer Order ID";

        if GenJnlLine.Amount < 0 then
            AppliesToDocType := GenJnlLine."Applies-to Doc. Type"::Invoice
        else
            AppliesToDocType := GenJnlLine."Applies-to Doc. Type"::"Credit Memo";

        if AppliesToDocNo = '' then begin
            OldCustLedgEntry.Reset();
            OldCustLedgEntry.SetCurrentKey("Document No.");
            OldCustLedgEntry.SetRange("Document Type", AppliesToDocType);
            OldCustLedgEntry.SetRange("Document No.", DocNumber);
            OldCustLedgEntry.SetRange("Customer No.", SellToCustNo);
            OldCustLedgEntry.SetRange(Open, true);
            OldCustLedgEntry.SetRange(Positive, GenJnlLine.Amount < 0);
            if OldCustLedgEntry.FindFirst() then begin
                GenJnlLine."Applies-to Doc. Type" := AppliesToDocType;
                GenJnlLine."Applies-to Doc. No." := DocNumber;
            end
            else begin
                if Transaction."Customer Order ID" <> '' then begin
                    GenJnlLine."Applies-to Doc. Type" := GenJnlLine."Applies-to Doc. Type"::" ";
                    GenJnlLine."Applies-to Doc. No." := '';
                    GenJnlLine."Applies-to ID" := DocNumber;
                end;
            end;
        end else begin
            OldCustLedgEntry.Reset();
            OldCustLedgEntry.SetCurrentKey("Document No.");
            OldCustLedgEntry.SetRange("Document Type", GenJnlLine."Document Type"::Invoice);
            OldCustLedgEntry.SetRange("Document No.", AppliesToDocNo);
            OldCustLedgEntry.SetRange("Customer No.", SellToCustNo);
            OldCustLedgEntry.SetRange(Open, true);
            OldCustLedgEntry.SetRange(Positive, GenJnlLine.Amount < 0);
            if OldCustLedgEntry.FindFirst() then begin
                GenJnlLine."Applies-to Doc. Type" := GenJnlLine."Document Type"::Invoice;
                GenJnlLine."Applies-to Doc. No." := AppliesToDocNo;
            end;
        end;
        GenJnlLine.Validate("VAT Reporting Date", Statement."VAT Reporting Date");
        OnAfterApplyGenJnlLine_PostPaymentToCustomer(GenJnlLine, Transaction, DocNumber, SellToCustNo, TotalAmountPaid, AppliesToDocNo);

        CreateGenJnlLineDim(
          GenJnlLine,
          DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
          DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
          Database::"LSC Store", Store."No.",
          Database::Customer, SellToCustNo, 0, '', '');
        AddSourceCurrency(GenJnlLine);
        OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
        GenJnlPostLine.SetPreviewMode(PreviewMode);
        GenJnlPostLine.RunWithCheck(GenJnlLine);
        TotalSum := TotalSum + GenJnlLine."Amount (LCY)";
    end;

    internal procedure TotalPayment(): Decimal
    var
        TotalAmountPaid: Decimal;
        TotalDepositAmt: Decimal;
    begin
        TransPmtEntry.Reset();
        TransPmtEntry.SetRange("Store No.", Transaction."Store No.");
        TransPmtEntry.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
        TransPmtEntry.SetRange("Transaction No.", Transaction."Transaction No.");
        if TransPmtEntry.FindSet() then
            repeat
                TenderType.Get(TransPmtEntry."Store No.", TransPmtEntry."Tender Type");
                if not (TenderType."Function" = TenderType."Function"::Customer) then
                    TotalAmountPaid := TotalAmountPaid + TransPmtEntry."Amount Tendered";

                if (TenderType."Function" = TenderType."Function"::Customer) and (Transaction."Customer Order") then
                    TotalDepositAmt := TotalDepositAmt + TransPmtEntry."Amount Tendered";
            until TransPmtEntry.Next() = 0;
        TotalAmountPaid := TotalAmountPaid + TotalDepositAmt;
        exit(TotalAmountPaid);
    end;

    internal procedure PostDiscountBuffering(Len: Integer; AccountNo: Code[20]; DiscAmount: Decimal; DiscVATAmount: Decimal; SalesTypeCode: Code[20])
    var
        GlobalDimension1Code: Code[20];
        GlobalDimension2Code: Code[20];
        EntryNo: Integer;
        IsHandled: Boolean;
    begin
#pragma warning disable AL0432
        OnBeforePostDiscountLedgerBuffering(PostingBuffer[1], GenPostingSetup, Len, Item, Store, BackOfficeSetup, TempDimBufNew, TableID, No, DiscAmount, IsHandled);
#pragma warning restore AL0432
        OnBeforePostDiscountLedgerBuffering2(PostingBuffer, GenPostingSetup, Len, Item, Store, BackOfficeSetup, TempDimBufNew, TableID, No, DiscAmount, TransSalesEntry, DiscVATAmount, IsHandled);
        if IsHandled then
            exit;

        TableID[3] := Database::"G/L Account";
        No[3] := AccountNo;

        GetDefaultDim(
            TableID, No, BackOfficeSetup."Source Code", GlobalDimension1Code,
            GlobalDimension2Code, Len);

        OnPostDiscountBuffering_OnAfterGetDefaultDim(Transaction, TransSalesEntry, TempDimBufNew, GlobalDimension1Code, GlobalDimension2Code);
        EntryNo := FindDimensions(TempDimBufNew);
        if EntryNo = 0 then
            EntryNo := InsertDimensions(TempDimBufNew);

        PostingBuffer[1]."Entry No." := EntryNo;
        PostingBuffer[1]."G/L Account" := AccountNo;
        PostingBuffer[1]."Department Code" := GlobalDimension1Code;
        PostingBuffer[1]."Project Code" := GlobalDimension2Code;
        PostingBuffer[1].Amount := DiscAmount;
        PostingBuffer[1]."VAT Base Amount" := DiscAmount;
        PostingBuffer[1]."VAT Amount" := DiscVATAmount;

        UpdPostingBuffer();
    end;

    procedure CreateDocNo(StoreNo: Code[10]; POSTerminalNo: Code[10]; TransactionNo: Integer) DocNo: Code[50]
    var
        LText001: Label 'The length of the Document No. (%1) can not exceed 20 characters.\The Document No. is constructed by concatenating the Store No. (%2), POS Terminal No. (%3) and the Transaction No. (%4) separated by "-".\Please make sure the combined length of the Store No. and the POS Terminal No. does not exceed 10 characters.';
    begin
        OnBeforeCreateDocNo(DocNo, StoreNo, POSTerminalNo, TransactionNo);
        DocNo := StoreNo + '-' +
          POSTerminalNo + '-' +
          Format(TransactionNo);
        OnAfterCreateDocNo(DocNo, StoreNo, POSTerminalNo, TransactionNo);
        if StrLen(DocNo) > 20 then
            Error(LText001, DocNo, StoreNo, POSTerminalNo, TransactionNo);
    end;

    procedure ExplodeDocNo(DocNo: Code[20]; StatementNo: Code[20]; var StoreNo: Code[10]; var PosNo: Code[10]; var TransNo: Integer)
    var
        PostedStatementLoc: Record "LSC Posted Statement";
        Position: Integer;
    begin
        PostedStatementLoc.Get(StatementNo);
        StoreNo := PostedStatementLoc."Store No.";
        DocNo := CopyStr(DocNo, StrLen(StoreNo) + 2);

        Position := StrPos(DocNo, '-');
        PosNo := CopyStr(DocNo, 1, Position);
        DocNo := CopyStr(DocNo, Position + 1);

        repeat
            Position := StrPos(DocNo, '-');
            if Position <> 0 then begin
                PosNo := PosNo + CopyStr(DocNo, 1, Position);
                DocNo := CopyStr(DocNo, Position + 1);
            end else
                Evaluate(TransNo, DocNo);
        until Position = 0;

        PosNo := CopyStr(PosNo, 1, StrLen(PosNo) - 1);
    end;

    procedure SetRunningFromBatchPosting()
    begin
        RunningFromBatchPosting := true;
    end;

    internal procedure SaveTempDimBufNew(FieldNumber: Integer; ShortcutDimCode: Code[20])
    begin
        GetGLSetup();
        TempDimBufNew.SetRange("Dimension Code", GLSetupShortcutDimCode[FieldNumber]);
        if ShortcutDimCode <> '' then begin
            if TempDimBufNew.FindFirst() then begin
                TempDimBufNew.Validate("Dimension Value Code", ShortcutDimCode);
                TempDimBufNew.Modify();
            end else begin
                TempDimBufNew.Init();
                TempDimBufNew.Validate("Table ID", 0);
                TempDimBufNew.Validate("Entry No.", 0);
                TempDimBufNew.Validate("Dimension Code", GLSetupShortcutDimCode[FieldNumber]);
                TempDimBufNew.Validate("Dimension Value Code", ShortcutDimCode);
                TempDimBufNew.Insert();
            end;
        end else
            if TempDimBufNew.FindFirst() then
                if TempDimBufNew."New Dimension Value Code" = '' then
                    TempDimBufNew.Delete
                else begin
                    TempDimBufNew."Dimension Value Code" := '';
                    TempDimBufNew.Modify();
                end;
        TempDimBufNew.Reset();
    end;

    internal procedure FindSalesType(pSalesType: Code[20])
    begin
        if pSalesType = '' then
            Clear(SalesTypes)
        else
            if pSalesType <> SalesTypes.Code then
                SalesTypes.Get(pSalesType);
    end;

    internal procedure BOMCalcStdCost(pItemNo: Code[20]; pDate: Date)
    var
        ItemLoc: Record Item;
        BOMComp: Record "BOM Component";
        TmpItem: Record Item temporary;
        CalculateStdCost: Codeunit "Calculate Standard Cost";
        ItemCostMgt: Codeunit ItemCostManagement;
    begin
        BOMComp.Reset();
        BOMComp.SetRange("Parent Item No.", pItemNo);
        BOMComp.SetRange(Type, Enum::"BOM Component Type"::Item);
        BOMComp.SetFilter("No.", '<>%1', '');
        if BOMComp.FindSet() then
            repeat
                ItemLoc.Get(BOMComp."No.");
                ItemLoc.CalcFields("Assembly BOM");
                if ItemLoc."Assembly BOM" then
                    BOMCalcStdCost(ItemLoc."No.", pDate);
            until BOMComp.Next() = 0;

        ItemLoc.Get(pItemNo);
        if ItemLoc."Costing Method" = ItemLoc."Costing Method"::Standard then
            if not BOMItemBuffer2.Get('', '', pItemNo, '', pDate, false) then begin
                BOMItemBuffer2.Init();
                BOMItemBuffer2."Item No." := pItemNo;
                BOMItemBuffer2.Date := pDate;
                BOMItemBuffer2.Insert();

                TmpItem.Reset();
                TmpItem.DeleteAll();
                Clear(CalculateStdCost);
                CalculateStdCost.SetProperties(pDate, false, true, true, '', false);
                ItemLoc.SetRange("No.", ItemLoc."No.");
                CalculateStdCost.CalcItems(ItemLoc, TmpItem);
                if TmpItem.FindSet() then
                    repeat
                        ItemCostMgt.UpdateStdCostShares(TmpItem);
                    until TmpItem.Next() = 0;
                if ItemLoc."LSC Recipe Item Type" = ItemLoc."LSC Recipe Item Type"::Recipe then begin
                    BOMComp.Reset();
                    BOMComp.SetRange("Parent Item No.", ItemLoc."No.");
                    if BOMComp.FindFirst() then
                        repeat
                            BOMComp.Validate("LSC Gross Weight");
                            BOMComp.Modify(true);
                        until BOMComp.Next() = 0;
                end;
            end;
    end;

    internal procedure CreateServItemOnTransSalesEnt(TransactionHeader: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry"; StatementNo: Code[20])
    var
        ServMgtSetup: Record "Service Mgt. Setup";
        ItemLoc: Record Item;
        GeneralLedgerSetup: Record "General Ledger Setup";
        ItemTrackingCode: Record "Item Tracking Code";
        ServItemGr: Record "Service Item Group";
        ServItem: Record "Service Item";
        ItemUnitOfMeasure: Record "Item Unit of Measure";
        ResSkillMgt: Codeunit "Resource Skill Mgt.";
        ServLogMgt: Codeunit ServLogManagement;
        x: Integer;
        IsHandled: Boolean;
        Text052: Label 'Posting cannot be completed successfully. %1 %2  belongs to the %3 that requires creating service items. Check if the %4 field contains a whole number.';
    begin
        OnBeforeCreateServItemOnTransSalesEnt(TransactionHeader, TransSalesEntry, StatementNo, TransSalesEntryStatus, Item, ItemPostingBuffer[1], IsHandled);
        if IsHandled then
            exit;

        ServMgtSetup.Get();
        GeneralLedgerSetup.Get();

        if not Store.Get(TransactionHeader."Store No.") then
            Store.Init();

        if TransSalesEntry.Quantity < 0 then begin
            ItemLoc.Get(TransSalesEntry."Item No.");
            if not ItemTrackingCode.Get(ItemLoc."Item Tracking Code") then
                ItemTrackingCode.Init();
            if (ServItemGr.Get(ItemLoc."Service Item Group")) and (ServItemGr."Create Service Item") then begin
                if TransSalesEntry.Quantity <> Round(TransSalesEntry.Quantity, 1) then
                    Error(
                      Text052,
                      ItemLoc.TableCaption,
                      ItemLoc."No.",
                      ServItemGr.TableCaption,
                      TransSalesEntry.FieldCaption(Quantity));

                for x := 1 to -TransSalesEntry.Quantity do begin
                    Clear(ServItem);
                    ServItem.Init();
                    ServMgtSetup.TestField("Service Item Nos.");
                    ServItem."No." := NoSeries.GetNextNo(ServMgtSetup."Service Item Nos.", 0D);
                    ServItem.Insert();
                    ServItem."Sales/Serv. Shpt. Document No." := StatementNo;
                    ServItem."Sales/Serv. Shpt. Line No." := 0;
                    ServItem.Validate(
                      Description,
                      CopyStr(ItemLoc.Description, 1, MaxStrLen(ServItem.Description)));
                    ServItem."Description 2" := CopyStr(
                      StrSubstNo('%1 %2', Statement.TableCaption, StatementNo),
                      1, MaxStrLen(ServItem."Description 2"));
                    ServItem.Validate("Customer No.", TransactionHeader."Customer No.");
                    ServItem.OmitAssignResSkills(true);
                    ServItem.Validate("Item No.", ItemLoc."No.");
                    ServItem.OmitAssignResSkills(false);
                    ServItem."Serial No." := TransSalesEntry."Serial No.";
                    ServItem."Variant Code" := TransSalesEntry."Variant Code";

                    ItemUnitOfMeasure.Get(ItemLoc."No.", TransSalesEntry."Unit of Measure");

                    ServItem.Validate("Sales Unit Cost", Round(ItemLoc."Unit Cost" /
                      ItemUnitOfMeasure."Qty. per Unit of Measure", GeneralLedgerSetup."Unit-Amount Rounding Precision"));
                    ServItem.Validate("Sales Unit Price", Round(TransSalesEntry."Net Price" /
                      ItemUnitOfMeasure."Qty. per Unit of Measure", GeneralLedgerSetup."Unit-Amount Rounding Precision"));
                    ServItem."Vendor No." := ItemLoc."Vendor No.";
                    ServItem."Vendor Item No." := ItemLoc."Vendor Item No.";
                    ServItem."Unit of Measure Code" := ItemLoc."Base Unit of Measure";
                    ServItem."Sales Date" := TransactionHeader.Date;
                    ServItem."Installation Date" := TransactionHeader.Date;
                    ServItem."Warranty % (Parts)" := ServMgtSetup."Warranty Disc. % (Parts)";
                    ServItem."Warranty % (Labor)" := ServMgtSetup."Warranty Disc. % (Labor)";
                    ServItem."Warranty Starting Date (Parts)" := TransactionHeader.Date;
                    if Format(ItemTrackingCode."Warranty Date Formula") <> '' then
                        ServItem."Warranty Ending Date (Parts)" :=
                          CalcDate(ItemTrackingCode."Warranty Date Formula", TransactionHeader.Date)
                    else
                        ServItem."Warranty Ending Date (Parts)" :=
                          CalcDate(
                            ServMgtSetup."Default Warranty Duration",
                            TransactionHeader.Date);
                    ServItem."Warranty Starting Date (Labor)" := TransactionHeader.Date;
                    ServItem."Warranty Ending Date (Labor)" :=
                      CalcDate(
                        ServMgtSetup."Default Warranty Duration",
                        TransactionHeader.Date);
                    ServItem.Modify();
                    ResSkillMgt.AssignServItemResSkills(ServItem);
                    Clear(ServLogMgt);
                    ServLogMgt.ServItemAutoCreated(ServItem);
                end;
            end;
        end;
    end;

    internal procedure CompressItemPostingBuffer()
    var
        ItemPostingBufferAux: Record "LSC Item Posting Buffer V2";
        DiscBuffer_Temp: Record "LSC Discount Ledger Entry" temporary;
    begin
        if ItemPostingBuffer[1]."Neg. Qty" then
            if ItemPostingBuffer[2].Get(ItemPostingBuffer[1].Type, ItemPostingBuffer[1]."Item No.", ItemPostingBuffer[1]."Location Code",
               ItemPostingBuffer[1]."Department Code", ItemPostingBuffer[1]."Document No.",
               ItemPostingBuffer[1]."Source No.",
               ItemPostingBuffer[1]."Serial No.", ItemPostingBuffer[1]."Lot No.",
               ItemPostingBuffer[1].Date, ItemPostingBuffer[1]."Salesperson Code",
               false, ItemPostingBuffer[1]."Currency Code",
               ItemPostingBuffer[1]."Offer No.",
               ItemPostingBuffer[1]."Promotion No.", ItemPostingBuffer[1]."Entry No.")
            then
                if ItemPostingBuffer[1].Quantity + ItemPostingBuffer[2].Quantity <> 0 then begin
                    SumItemPostingBuffer(1);
                    ItemPostingBuffer[2].Delete();
                    DiscLedgerMgt.SumDiscBuffer(ItemPostingBuffer[2]."Discount Entry No.", ItemPostingBuffer[1]."Discount Entry No.");
                    DiscLedgerMgt.DeleteDiscBuffer(ItemPostingBuffer[2]."Discount Entry No.");
                end else
                    if (ItemPostingBuffer[2]."Serial No." <> '') and (ItemPostingBuffer[2].Quantity <> 0) then begin
                        ItemPostingBufferAux := ItemPostingBuffer[2];

                        ItemPostingBufferAux.Quantity := -ItemPostingBufferAux.Quantity / ItemPostingBuffer[2].Quantity;
                        ItemPostingBufferAux.Amount := -ItemPostingBufferAux.Amount / ItemPostingBuffer[2].Quantity;
                        ItemPostingBufferAux."Cost Amount" := -ItemPostingBufferAux."Cost Amount" / ItemPostingBuffer[2].Quantity;
                        ItemPostingBufferAux."Line Discount Amount" := -ItemPostingBufferAux."Line Discount Amount" /
                          ItemPostingBuffer[2].Quantity;
                        ItemPostingBufferAux."Inv. Discount Amount" := -ItemPostingBufferAux."Inv. Discount Amount" /
                          ItemPostingBuffer[2].Quantity;
                        DiscLedgerMgt.GetDiscBufferFragtion(ItemPostingBufferAux."Discount Entry No.", -ItemPostingBuffer[2].Quantity,
                          DiscBuffer_Temp);
                        DiscLedgerMgt.SaveCurrDiscBuffer(DiscBuffer_Temp);

                        ItemPostingBuffer[2].Quantity := ItemPostingBuffer[2].Quantity -
                          ItemPostingBufferAux.Quantity;
                        ItemPostingBuffer[2].Amount := ItemPostingBuffer[2].Amount -
                          ItemPostingBufferAux.Amount;
                        ItemPostingBuffer[2]."Cost Amount" := ItemPostingBuffer[2]."Cost Amount" -
                          ItemPostingBufferAux."Cost Amount";
                        ItemPostingBuffer[2]."Line Discount Amount" := ItemPostingBuffer[2]."Line Discount Amount" -
                          ItemPostingBufferAux."Line Discount Amount";
                        ItemPostingBuffer[2]."Inv. Discount Amount" := ItemPostingBuffer[2]."Inv. Discount Amount" -
                          ItemPostingBufferAux."Inv. Discount Amount";
                        OnBeforeItemPostingBufferModifyInCompressItemPostingBufferV2(ItemPostingBufferAux, ItemPostingBuffer[2]);
                        ItemPostingBuffer[2].Modify();
                        DiscLedgerMgt.RevertSignCurrDiscBuffer();
                        DiscLedgerMgt.GetCurrDiscBuffer(DiscBuffer_Temp);
                        DiscLedgerMgt.UpdateDiscBuffer(ItemPostingBuffer[2]."Discount Entry No.", DiscBuffer_Temp);
                        SumItemPostingBuffer(1);
                        DiscLedgerMgt.SumDiscBuffer(ItemPostingBuffer[2]."Discount Entry No.", ItemPostingBuffer[1]."Discount Entry No.");
                        DiscLedgerMgt.DeleteDiscBuffer(ItemPostingBuffer[2]."Discount Entry No.");

                        ItemPostingBuffer[2] := ItemPostingBufferAux;
                        ItemPostingBuffer[2].Modify();
                        DiscLedgerMgt.RevertSignCurrDiscBuffer();
                        DiscLedgerMgt.GetCurrDiscBuffer(DiscBuffer_Temp);
                        DiscLedgerMgt.UpdateDiscBuffer(ItemPostingBuffer[2]."Discount Entry No.", DiscBuffer_Temp);
                    end;
    end;

    internal procedure NextEntryShouldBePositive(var pItemPostingBuffer: Record "LSC Item Posting Buffer V2"): Boolean
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        ItemLedgerEntry.Reset();
        ItemLedgerEntry.SetCurrentKey("Item No.", Open, "Variant Code", Positive,
          "Location Code", "Posting Date", "Expiration Date", "Lot No.", "Serial No.");
        ItemLedgerEntry.SetRange("Item No.", pItemPostingBuffer."Item No.");
        ItemLedgerEntry.SetRange("Variant Code", pItemPostingBuffer."Source No.");
        ItemLedgerEntry.SetRange("Location Code", pItemPostingBuffer."Location Code");
        ItemLedgerEntry.SetRange("Serial No.", pItemPostingBuffer."Serial No.");
        ItemLedgerEntry.SetRange(Open, true);
        ItemLedgerEntry.SetRange(Positive, true);
        exit(ItemLedgerEntry.IsEmpty());
    end;

    internal procedure LotInventoryAvailable(var pItemPostingBuffer: Record "LSC Item Posting Buffer V2"): Boolean
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        ItemLedgerEntry.Reset();
        ItemLedgerEntry.SetCurrentKey("Item No.", Open, "Variant Code", Positive,
          "Location Code", "Posting Date", "Expiration Date", "Lot No.", "Serial No.");
        ItemLedgerEntry.SetRange("Item No.", pItemPostingBuffer."Item No.");
        ItemLedgerEntry.SetRange("Variant Code", pItemPostingBuffer."Source No.");
        ItemLedgerEntry.SetRange("Location Code", pItemPostingBuffer."Location Code");
        ItemLedgerEntry.SetRange("Lot No.", pItemPostingBuffer."Lot No.");
        ItemLedgerEntry.CalcSums(Quantity);

        if ItemLedgerEntry.Quantity < pItemPostingBuffer.Quantity then
            exit(false)
        else
            exit(true);
    end;

    internal procedure OkToPostDirect(var pItemPostingBuffer: Record "LSC Item Posting Buffer V2"): Boolean
    var
        PostDirect: Boolean;
    begin
        if pItemPostingBuffer."Serial No." <> '' then
            if pItemPostingBuffer.Quantity <= 0 then
                if NextEntryShouldBePositive(pItemPostingBuffer) then
                    PostDirect := true
                else
                    PostDirect := false
            else
                if NextEntryShouldBePositive(pItemPostingBuffer) then
                    PostDirect := false
                else
                    PostDirect := true
        else
            if pItemPostingBuffer.Quantity <= 0 then
                PostDirect := true
            else
                if LotInventoryAvailable(pItemPostingBuffer) then
                    PostDirect := true
                else
                    PostDirect := false;

        exit(PostDirect);
    end;

    internal procedure FindReversePosting(var pItemPostingBuffer_In: Record "LSC Item Posting Buffer V2"; var pItemPostingBuffer_Out: Record "LSC Item Posting Buffer V2"): Boolean
    begin
        ItemPostingBuffer[2].Reset();
        ItemPostingBuffer[2].SetRange(Type, pItemPostingBuffer_In.Type);
        ItemPostingBuffer[2].SetRange("Item No.", pItemPostingBuffer_In."Item No.");
        ItemPostingBuffer[2].SetFilter("Source No.", '%1', pItemPostingBuffer_In."Source No.");
        ItemPostingBuffer[2].SetRange("Location Code", pItemPostingBuffer_In."Location Code");
        ItemPostingBuffer[2].SetRange("Serial No.", pItemPostingBuffer_In."Serial No.");
        ItemPostingBuffer[2].SetRange("Neg. Qty", not pItemPostingBuffer_In."Neg. Qty");
        if ItemPostingBuffer[2].FindFirst() then begin
            pItemPostingBuffer_Out := ItemPostingBuffer[2];
            ItemPostingBuffer[2].Delete();
            exit(true);
        end else begin
            Clear(pItemPostingBuffer_Out);
            exit(false);
        end;
    end;

    internal procedure PostDepositPayments(CustomerNo: Code[20])
    var
        TransPmtEntryLoc: Record "LSC Trans. Payment Entry";
        TenderTypeLoc: Record "LSC Tender Type";
        Text053: Label 'Tender Type specifically used for deposits is missing for Store %1';
    begin
        TenderTypeLoc.SetRange("Store No.", Transaction."Store No.");
        TenderTypeLoc.SetRange("Function", TenderTypeLoc."Function"::Customer);
        if TenderTypeLoc.FindSet() then
            repeat
                TransPmtEntryLoc.SetRange("Store No.", Transaction."Store No.");
                TransPmtEntryLoc.SetRange("POS Terminal No.", Transaction."POS Terminal No.");
                TransPmtEntryLoc.SetRange("Transaction No.", Transaction."Transaction No.");
                TransPmtEntryLoc.SetRange("Tender Type", TenderTypeLoc.Code);
                if TransPmtEntryLoc.FindSet() then
                    repeat
                        PostPaymentToCustomer(Transaction."Customer Order ID", CustomerNo, -TransPmtEntryLoc."Amount Tendered",
                            FindSalesOrderPrepaymentInv(Transaction."Customer Order ID"));
                    until TransPmtEntryLoc.Next() = 0;
            until TenderTypeLoc.Next() = 0
        else
            Error(Text053, Transaction."Store No.");
    end;

    internal procedure FindSalesOrderPrepaymentInv(DocumentNo: Code[20]): Code[20]
    var
        SalesInvHeader: Record "Sales Invoice Header";
    begin
        SalesInvHeader.SetCurrentKey("Prepayment Order No.", "Prepayment Invoice");
        SalesInvHeader.SetRange("Prepayment Order No.", DocumentNo);
        SalesInvHeader.SetRange("Prepayment Invoice", true);
        if SalesInvHeader.FindFirst() then
            exit(SalesInvHeader."No.");
    end;

    internal procedure CreateDiscBuffer(var TransDiscountEntryTemp: Record "LSC Trans. Discount Entry" temporary; var pTransSalesEntry: Record "LSC Trans. Sales Entry"; pVATFactor: Decimal)
    var
        DiscBuffer: Record "LSC Discount Ledger Entry" temporary;
    begin
        TransDiscountEntryTemp.Reset();
        TransDiscountEntryTemp.SetRange("Store No.", pTransSalesEntry."Store No.");
        TransDiscountEntryTemp.SetRange("POS Terminal No.", pTransSalesEntry."POS Terminal No.");
        TransDiscountEntryTemp.SetRange("Transaction No.", pTransSalesEntry."Transaction No.");
        TransDiscountEntryTemp.SetRange("Line No.", pTransSalesEntry."Line No.");
        if TransDiscountEntryTemp.FindSet() then
            repeat
                DiscBuffer.Init();
                DiscBuffer."Offer Type" := TransDiscountEntryTemp."Offer Type";
                DiscBuffer."Offer No." := TransDiscountEntryTemp."Offer No.";
                if glUndoItemPosting then
                    DiscBuffer.Quantity := TransSalesEntry.Quantity
                else
                    DiscBuffer.Quantity := -TransSalesEntry.Quantity;
                DiscBuffer."Sales Amount" := -TransSalesEntry."Net Amount";
                DiscBuffer."Discount Amount" := Round(TransDiscountEntryTemp."Discount Amount" / pVATFactor);
                DiscBuffer.Insert();
            until TransDiscountEntryTemp.Next() = 0;
        DiscLedgerMgt.SaveCurrDiscBuffer(DiscBuffer);
    end;

    internal procedure InsertSalesLineDiscEntry(var TransDiscountEntryTemp: Record "LSC Trans. Discount Entry" temporary; var pTransSalesEntry: Record "LSC Trans. Sales Entry"; var pSalesLine: Record "Sales Line")
    var
        SalesLineDiscEntry: Record "LSC Sales Line Discount Entry";
    begin
        TransDiscountEntryTemp.Reset();
        TransDiscountEntryTemp.SetRange("Store No.", pTransSalesEntry."Store No.");
        TransDiscountEntryTemp.SetRange("POS Terminal No.", pTransSalesEntry."POS Terminal No.");
        TransDiscountEntryTemp.SetRange("Transaction No.", pTransSalesEntry."Transaction No.");
        TransDiscountEntryTemp.SetRange("Line No.", pTransSalesEntry."Line No.");
        if TransDiscountEntryTemp.FindSet() then
            repeat
                InitSalesLineDiscEntry(pSalesLine, SalesLineDiscEntry);
                SalesLineDiscEntry."Offer Type" := TransDiscountEntryTemp."Offer Type";
                SalesLineDiscEntry."Offer No." := TransDiscountEntryTemp."Offer No.";
                SalesLineDiscEntry."Discount Amount" := TransDiscountEntryTemp."Discount Amount";
                SalesLineDiscEntry.Insert();
            until TransDiscountEntryTemp.Next() = 0;
    end;

    internal procedure InitSalesLineDiscEntry(var pSalesLine: Record "Sales Line"; var pSalesLineDiscEntry: Record "LSC Sales Line Discount Entry")
    begin
        pSalesLineDiscEntry.Init();
        pSalesLineDiscEntry."Document Type" := pSalesLine."Document Type";
        pSalesLineDiscEntry."Document No." := pSalesLine."Document No.";
        pSalesLineDiscEntry."Document Line No." := pSalesLine."Line No.";
    end;

    internal procedure GetTransLineDiscAmount(var TransDiscEntryTemp: Record "LSC Trans. Discount Entry" temporary; pTransSalesEntry: Record "LSC Trans. Sales Entry"; OfferType: Enum "LSC Trans. Disc. Ent Offer Typ"): Decimal
    begin
        TransDiscEntryTemp.SetRange("Store No.", pTransSalesEntry."Store No.");
        TransDiscEntryTemp.SetRange("POS Terminal No.", pTransSalesEntry."POS Terminal No.");
        TransDiscEntryTemp.SetRange("Transaction No.", pTransSalesEntry."Transaction No.");
        TransDiscEntryTemp.SetRange("Line No.", pTransSalesEntry."Line No.");
        TransDiscEntryTemp.SetRange("Offer Type", OfferType);
        if TransDiscEntryTemp.FindFirst() then
            exit(TransDiscEntryTemp."Discount Amount");
    end;

    internal procedure CalculateTransactionDiscounts(var TransDiscEntryTemp: Record "LSC Trans. Discount Entry" temporary; StatementNo: Code[20])
    var
        StatementPostDiscounts: Query "BMG Statement Post Discounts";
    begin
        //!!!
        StatementPostDiscounts.SetRange(StatementNo, StatementNo);
        StatementPostDiscounts.Open();
        while StatementPostDiscounts.Read() do begin
            TransDiscEntryTemp."Store No." := StatementPostDiscounts.StoreNo;
            TransDiscEntryTemp."POS Terminal No." := StatementPostDiscounts.POSTerminalNo;
            TransDiscEntryTemp."Transaction No." := StatementPostDiscounts.TransactionNo;
            TransDiscEntryTemp."Line No." := StatementPostDiscounts.LineNo;
            TransDiscEntryTemp."Offer Type" := StatementPostDiscounts.OfferType;
            TransDiscEntryTemp."Discount Amount" := StatementPostDiscounts.DiscountAmount;
            TransDiscEntryTemp.Insert();
        end;

    end;

    internal procedure TestDeleteHeader(pStatement: Record "LSC Statement"; var pPostedStatement: Record "LSC Posted Statement")
    var
        SourceCodeSetup: Record "Source Code Setup";
    begin
        Clear(pPostedStatement);
        SourceCodeSetup.Get();
        SourceCodeSetup.TestField("Deleted Document");
        SourceCode.Get(SourceCodeSetup."Deleted Document");
        if (pStatement."Posting Nos." <> '') and
          ((pStatement."Posting No." <> '') or (pStatement."No. Series." = pStatement."Posting Nos."))
        then begin
            pPostedStatement.TransferFields(pStatement);
            if pStatement."Posting No." <> '' then
                pPostedStatement."No." := pStatement."Posting No.";
            pPostedStatement."Pre-Assign. No. Series" := pStatement."No. Series.";
            pPostedStatement."No. Series." := pStatement."Posting Nos.";
            pPostedStatement."Pre-Assigned No." := pStatement."No.";
        end;
    end;

    internal procedure DeleteStatementHeader(var pStatement: Record "LSC Statement"; var pPostedStatement: Record "LSC Posted Statement")
    var
        lPostedStatemLine: Record "LSC Posted Statement Line";
    begin
        TestDeleteHeader(pStatement, pPostedStatement);
        if pStatement.Get(pStatement."Store No.", pStatement."No.") then
            pStatement.Delete();
        if pPostedStatement."No." <> '' then begin
            pPostedStatement.Insert();
            lPostedStatemLine.Init();
            lPostedStatemLine."Statement No." := pPostedStatement."No.";
            lPostedStatemLine."Line No." := 10000;
            lPostedStatemLine."Tender Type Name" := CopyStr(SourceCode.Description, 1, MaxStrLen(lPostedStatemLine."Tender Type Name"));
            lPostedStatemLine.Insert();
        end;
    end;

    internal procedure UpdatePaymentBuffer(pAccountType: Enum "LSC Tender Posting Acc. Type"; pAccountNo: Code[20]; pDescription: Text[50]; pCurrencyCode: Code[10]; pAmount: Decimal; pAmountLCY: Decimal)
    var
        BufferLineNo: Integer;
        IsHandled: Boolean;
    begin
        OnBeforeUpdatePaymentBuffer(PaymPostingBuffer, pAccountType, pAccountNo, pDescription, pCurrencyCode, pAmount, pAmountLCY, BufferLineNo, IsHandled);
        if IsHandled then
            exit;

        PaymPostingBuffer.Reset();
        if pAccountType = pAccountType::"G/L Account" then
            PaymPostingBuffer.SetRange(Type, PaymPostingBuffer.Type::"G/L Account")
        else
            PaymPostingBuffer.SetRange(Type, PaymPostingBuffer.Type::"Bank Account");
        PaymPostingBuffer.SetRange("G/L Account", pAccountNo);
        PaymPostingBuffer.SetFilter("Currency Code", '%1', pCurrencyCode);

        if not PaymPostingBuffer.FindFirst() then begin
            BufferLineNo += 1;
            PaymPostingBuffer.Init();
            if pAccountType = pAccountType::"G/L Account" then
                PaymPostingBuffer.Type := PaymPostingBuffer.Type::"G/L Account"
            else
                PaymPostingBuffer.Type := PaymPostingBuffer.Type::"Bank Account";
            PaymPostingBuffer."G/L Account" := pAccountNo;
            PaymPostingBuffer."Currency Code" := pCurrencyCode;
            PaymPostingBuffer."Entry No." := BufferLineNo;
            PaymPostingBuffer."Payment Posting Description" := pDescription;
            PaymPostingBuffer.Insert();
        end;

        PaymPostingBuffer."POS Line Disc. Amount" += pAmountLCY;
        PaymPostingBuffer.Amount += pAmount;
        PaymPostingBuffer.Modify();
        OnAfterUpdatePaymentBuffer(PaymPostingBuffer);
    end;

    internal procedure PostPaymentBuffer()
    var
        Description: Text;
        lCurrencyGainLoss: Decimal;
    begin
        PaymPostingBuffer.Reset();
        if PaymPostingBuffer.FindSet() then
            repeat
                lCurrencyGainLoss := 0;
                if PaymPostingBuffer.Type = PaymPostingBuffer.Type::"G/L Account" then
                    GenJournalAccType := GenJournalAccType::"G/L Account"
                else
                    GenJournalAccType := GenJournalAccType::"Bank Account";
                Description := PaymPostingBuffer."Payment Posting Description";
                CreateInitialGenJnlLine(Statement, GenJnlLine, GenJournalAccType, PaymPostingBuffer."G/L Account", Description, PaymPostingBuffer.Amount);
                if PaymPostingBuffer."Currency Code" <> '' then begin
                    GenJnlLine.Validate("Currency Code", PaymPostingBuffer."Currency Code");
                    lCurrencyGainLoss := GenJnlLine."Amount (LCY)" - PaymPostingBuffer."POS Line Disc. Amount";
                end
                else
                    GenJnlLine.Validate("Currency Code", Store."Currency Code");
                GenJnlLine."VAT Amount" := 0;
                GenJnlLine."VAT Posting" := GenJnlLine."VAT Posting"::"Manual VAT Entry";
                GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
                GenJnlLine.Validate("VAT Reporting Date", Statement."VAT Reporting Date");

                CreateGenJnlLineDim(
                    GenJnlLine,
                    DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
                    DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
                    Database::"LSC Store", Store."No.", 0, '', 0, '', '');
                if GenJnlLine."Amount (LCY)" <> 0 then begin
                    AddSourceCurrency(GenJnlLine);
                    OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
                    GenJnlPostLine.SetPreviewMode(PreviewMode);
                    GenJnlPostLine.RunWithCheck(GenJnlLine);
                end;
                TotalSum := TotalSum + GenJnlLine."Amount (LCY)";

                if lCurrencyGainLoss <> 0 then begin
                    Currency.Get(PaymPostingBuffer."Currency Code");
                    if lCurrencyGainLoss > 0 then
                        GLAccount.Get(Currency."Realized Gains Acc.")
                    else
                        GLAccount.Get(Currency."Realized Losses Acc.");
                    Description := CopyStr(StrSubstNo(Text054, PaymPostingBuffer."Payment Posting Description", PaymPostingBuffer."Currency Code"), 1, 50);
                    CreateInitialGenJnlLine(Statement, GenJnlLine, GenJournalAccType::"G/L Account", GLAccount."No.", Description, -lCurrencyGainLoss);
                    GenJnlLine."Source Code" := BackOfficeSetup."Source Code";
                    GenJnlLine.Validate("VAT Reporting Date", Statement."VAT Reporting Date");

                    CreateGenJnlLineDim(
                        GenJnlLine,
                        DimManagement.TypeToTableID1(GenJnlLine."Account Type".AsInteger()), GenJnlLine."Account No.",
                        DimManagement.TypeToTableID1(GenJnlLine."Bal. Account Type".AsInteger()), GenJnlLine."Bal. Account No.",
                        Database::"LSC Store", Store."No.", 0, '', 0, '', '');
                    if GenJnlLine."Amount (LCY)" <> 0 then begin
                        AddSourceCurrency(GenJnlLine);
                        OnBeforeGenJnlLineRunWithCheckInStatementPost(GenJnlLine, Transaction);
                        GenJnlPostLine.SetPreviewMode(PreviewMode);
                        GenJnlPostLine.RunWithCheck(GenJnlLine);
                    end;
                    TotalSum := TotalSum + GenJnlLine."Amount (LCY)";
                end;
            until PaymPostingBuffer.Next() = 0;
        PaymPostingBuffer.DeleteAll();
    end;

    internal procedure CheckTransSubTables(Transaction_p: Record "LSC Transaction Header") Result: Boolean
    var
        TransSalesEntry_l: Record "LSC Trans. Sales Entry";
        TransPaymEntry_l: Record "LSC Trans. Payment Entry";
    begin
        Result := true;
        if Transaction_p."No. of Item Lines" <> 0 then begin
            TransSalesEntry_l.SetRange("Store No.", Transaction_p."Store No.");
            TransSalesEntry_l.SetRange("POS Terminal No.", Transaction_p."POS Terminal No.");
            TransSalesEntry_l.SetRange("Transaction No.", Transaction_p."Transaction No.");
            Result := Result and (Transaction_p."No. of Item Lines" - TransSalesEntry_l.Count = 0);
        end;
        if Transaction_p."No. of Payment Lines" <> 0 then begin
            TransPaymEntry_l.SetRange("Store No.", Transaction_p."Store No.");
            TransPaymEntry_l.SetRange("POS Terminal No.", Transaction_p."POS Terminal No.");
            TransPaymEntry_l.SetRange("Transaction No.", Transaction_p."Transaction No.");
            Result := Result and (Transaction_p."No. of Payment Lines" - TransPaymEntry_l.Count = 0);
        end;
    end;

    local procedure SetTransInvAdjmtEntryStatus(var TransactionStatus: Record "LSC Transaction Status")
    var
        TransInvAdjmtEntry: Record "LSC Trans. Inv. Adjmt. Entry";
        TransInvAdjmtEntrySt: Record "LSC Trans. Inv Adjmt. Entry St";
    begin
        TransInvAdjmtEntry.Reset();
        TransInvAdjmtEntry.SetRange("Store No.", TransactionStatus."Store No.");
        TransInvAdjmtEntry.SetRange("POS Terminal No.", TransactionStatus."POS Terminal No.");
        TransInvAdjmtEntry.SetRange("Transaction No.", TransactionStatus."Transaction No.");
        if TransInvAdjmtEntry.FindSet() then
            repeat
                if not TransInvAdjmtEntrySt.Get(TransInvAdjmtEntry."Store No.", TransInvAdjmtEntry."POS Terminal No.", TransInvAdjmtEntry."Transaction No.",
                    TransInvAdjmtEntry."Line No.", TransInvAdjmtEntry."Location Code")
                then begin
                    TransInvAdjmtEntrySt.Init();
                    TransInvAdjmtEntrySt.TransferFields(TransInvAdjmtEntry, true);
                    TransInvAdjmtEntrySt.Status := TransactionStatus.Status;
                    TransInvAdjmtEntrySt.Insert(true);
                end else begin
                    TransInvAdjmtEntrySt.Status := TransactionStatus.Status;
                    TransInvAdjmtEntrySt.Modify(true);
                end;
            until TransInvAdjmtEntry.Next() = 0;
    end;

    local procedure ProcessItemAdjustPostBuffer(var PostingException_p: Record "LSC Posting Exception")
    begin
        ItemAdjustPostBuffer[1] := ItemPostingBuffer[1];
        ItemAdjustPostBuffer[1].Type := ItemAdjustPostBuffer[1].Type::ExPositiveAdjust;
        ItemAdjustPostBuffer[1]."Salesperson Code" := '';
        ItemAdjustPostBuffer[1]."Offer No." := '';
        ItemAdjustPostBuffer[1]."Promotion No." := '';
        UpdItemAdjustPostBuffer();

        ItemAdjustPostBuffer[1].Type := ItemAdjustPostBuffer[1].Type::ExNegativeAdjust;
        ItemAdjustPostBuffer[1]."Location Code" := PostingException_p."Sourcing Location Code";
        UpdItemAdjustPostBuffer();
    end;

    local procedure UpdItemAdjustPostBuffer()
    begin
        ItemAdjustPostBuffer[2] := ItemAdjustPostBuffer[1];
        if ItemAdjustPostBuffer[2].Find() then begin
            ItemAdjustPostBuffer[2].Quantity := ItemAdjustPostBuffer[2].Quantity + ItemAdjustPostBuffer[1].Quantity;
            ItemAdjustPostBuffer[2].Modify();
        end else begin
            if ItemAdjustPostBuffer[1].Type = ItemAdjustPostBuffer[1].Type::ExPositiveAdjust then
                ItemAdjustPostBuffer[1]."Adjustment Link No." := PostingExceptionUtility.GetNextEntryNo();
            ItemAdjustPostBuffer[1].Insert();
        end;
    end;

    local procedure PostItemAdjustment()
    var
        CodeDictionary_l: Dictionary of [Integer, Code[20]];
        DimSource_l: List of [Dictionary of [Integer, Code[20]]];
    begin
        OnBeforePostItemAdjustmentV2(ItemAdjustPostBuffer[1], Statement);
        GetItem(ItemAdjustPostBuffer[1]."Item No.", ItemAdjustPostBuffer[1], Item);
        TransPostingFunctions.SetItemBlockReserve(Item."No.");

        Clear(ItemJnlLine);
        ItemJnlLine.Init();
        ItemJnlLine."Item No." := ItemAdjustPostBuffer[1]."Item No.";
        ItemJnlLine."Variant Code" := ItemAdjustPostBuffer[1]."Source No.";
        ItemJnlLine."Posting Date" := ItemAdjustPostBuffer[1].Date;
        ItemJnlLine."Document Date" := Statement."Posting Date";
        if ItemAdjustPostBuffer[1].Type = ItemAdjustPostBuffer[1].Type::ExNegativeAdjust then
            ItemJnlLine.Validate("Entry Type", ItemJnlLine."Entry Type"::"Negative Adjmt.")
        else
            ItemJnlLine.Validate("Entry Type", ItemJnlLine."Entry Type"::"Positive Adjmt.");
        ItemJnlLine."Document No." := ItemAdjustPostBuffer[1]."Document No.";
        ItemJnlLine."LSC BO Doc. No." := Statement."Posting No.";
        ItemJnlLine.Description := Item.Description;
        ItemJnlLine."Location Code" := ItemAdjustPostBuffer[1]."Location Code";
        ItemJnlLine."Inventory Posting Group" := Item."Inventory Posting Group";
        ItemJnlLine."Source Posting Group" := '';
        if Item."Base Unit of Measure" <> '' then begin
            ItemJnlLine.Validate("Unit of Measure Code", Item."Base Unit of Measure");
            ItemJnlLine.Validate(Quantity, ItemAdjustPostBuffer[1].Quantity);
        end else begin
            ItemJnlLine."Unit of Measure Code" := '';
            ItemJnlLine."Qty. per Unit of Measure" := 1;
            ItemJnlLine.Validate("Quantity (Base)", ItemAdjustPostBuffer[1].Quantity);
        end;
        ItemJnlLine."Source Code" := BackOfficeSetup."Source Code";
        ItemJnlLine."Gen. Bus. Posting Group" := ItemAdjustPostBuffer[1]."Gen. Bus. Posting Group";
        ItemJnlLine."Gen. Prod. Posting Group" := ItemAdjustPostBuffer[1]."Gen. Prod. Posting Group";

        ItemJnlLine."Expiration Date" := ItemPostingBuffer[1]."Expiration Date";
        if (ItemPostingBuffer[1]."Serial No." <> '') or (ItemPostingBuffer[1]."Lot No." <> '') then
            TransPostingFunctions.AddSerialNoAndLotNoTracking(ItemJnlLine, ItemPostingBuffer[1]."Serial No.", ItemPostingBuffer[1]."Lot No.", ItemPostingBuffer[1]."Expiration Date");

        CodeDictionary_l.Add(Database::Item, ItemJnlLine."Item No.");
        AddToDimList(CodeDictionary_l, DimSource_l);
        CodeDictionary_l.Add(Database::"LSC Store", Store."No.");
        AddToDimList(CodeDictionary_l, DimSource_l);

        CreateItemJnlLineDim(ItemJnlLine, DimSource_l, '');

        OnBeforeItemJnlLinePostLineV2(ItemJnlLine, Statement, ItemPostingBuffer[1]);
        if not PreviewMode then
            ItemJnlPostLine.RunWithCheck(ItemJnlLine);
        OnAfterItemJnlLinePostLine(ItemJnlLine, Statement);
        ItemAdjustPostBuffer[1]."Item Ledger Entry No." := ItemJnlLine."Item Shpt. Entry No.";
        ItemAdjustPostBuffer[1].Modify();

        TransPostingFunctions.ResetItemBlockReserve();
    end;

    procedure CheckSerialNo(StoreNoIn: Code[10]; StatementNoIn: Code[20]; var ExplanationMsgOut: Text) ExplanationMsgFound: Boolean
    var
        Statement_L: Record "LSC Statement";
        TransactionStatus_L: Record "LSC Transaction Status";
        TransSalesEntry_L: Record "LSC Trans. Sales Entry";
        Item_L: Record Item;
        ItemTrackingCode_L: Record "Item Tracking Code";
        TransSalesEntry_TEMP: Record "LSC Trans. Sales Entry" temporary;
        TransSalesLineAlreadyPosted: Boolean;
        ExplanationMsg: Label 'Item %1 with Serial No. %2 was sold and returned on two different transactions, see receipts %3 and %4. The transactions must be selected on the same statement or their statements must be posted in a chronological order.';
    begin
        ExplanationMsgFound := false;
        ExplanationMsgOut := '';
        if not Statement_L.Get(StoreNoIn, StatementNoIn) then
            exit;
        Statement_L.CalcFields("Serial/Lot No. Not Valid");
        if Statement_L."Serial/Lot No. Not Valid" = 0 then
            exit;

        TransSalesEntry_TEMP.Reset();
        TransSalesEntry_TEMP.DeleteAll();
        TransSalesEntry_L.Reset();
        TransactionStatus_L.Reset();
        TransactionStatus_L.SetCurrentKey("Statement No.");
        TransactionStatus_L.SetRange("Statement No.", StatementNoIn);
        TransactionStatus_L.SetRange("Store No.", StoreNoIn);
        TransactionStatus_L.SetFilter("Serial/Lot No. Not Valid", '<>0');
        if TransactionStatus_L.FindSet() then
            repeat
                TransSalesEntry_L.SetRange("Store No.", TransactionStatus_L."Store No.");
                TransSalesEntry_L.SetRange("POS Terminal No.", TransactionStatus_L."POS Terminal No.");
                TransSalesEntry_L.SetRange("Transaction No.", TransactionStatus_L."Transaction No.");
                TransSalesEntry_L.SetRange("Serial/Lot No. Not Valid", true);
                if TransSalesEntry_L.FindSet() then
                    repeat
                        if Item_L.Get(TransSalesEntry_L."Item No.") then
                            if ItemTrackingCode_L.Get(Item_L."Item Tracking Code") then
                                if (ItemTrackingCode_L."SN Specific Tracking") or
                                    (ItemTrackingCode_L."SN Info. Outbound Must Exist") or
                                    (ItemTrackingCode_L."SN Sales Outbound Tracking") then begin
                                    TransSalesEntry_TEMP.Reset();
                                    TransSalesEntry_TEMP.SetRange("Item No.", TransSalesEntry_L."Item No.");
                                    TransSalesEntry_TEMP.SetFilter("Variant Code", '%1', TransSalesEntry_L."Variant Code");
                                    TransSalesEntry_TEMP.SetRange("Serial No.", TransSalesEntry_L."Serial No.");
                                    if TransSalesEntry_TEMP.FindFirst() then begin
                                        TransSalesEntry_TEMP.Quantity := TransSalesEntry_TEMP.Quantity + TransSalesEntry_L.Quantity;
                                        TransSalesEntry_TEMP.Modify();
                                    end
                                    else begin
                                        TransSalesEntry_TEMP := TransSalesEntry_L;
                                        TransSalesEntry_TEMP.Insert();
                                    end;
                                end;
                    until TransSalesEntry_L.Next() = 0;
            until TransactionStatus_L.Next() = 0;

        TransSalesEntry_TEMP.Reset();
        TransSalesEntry_TEMP.SetFilter(Quantity, '0');
        TransSalesEntry_TEMP.DeleteAll();
        TransSalesEntry_TEMP.SetRange(Quantity);

        if TransSalesEntry_TEMP.FindSet() then
            repeat
                TransSalesEntry_L.Reset();
                TransSalesEntry_L.SetCurrentKey("Item No.", "Variant Code", Date, "Store No.", "Serial No.", "Lot No.");
                TransSalesEntry_L.SetRange("Item No.", TransSalesEntry_TEMP."Item No.");
                TransSalesEntry_L.SetFilter("Variant Code", '%1', TransSalesEntry_TEMP."Variant Code");
                TransSalesEntry_L.SetRange("Store No.", TransSalesEntry_TEMP."Store No.");
                TransSalesEntry_L.SetRange("Serial No.", TransSalesEntry_TEMP."Serial No.");
                if TransSalesEntry_L.FindSet() then
                    repeat
                        TransSalesLineAlreadyPosted := false;
                        if TransactionStatus_L.Get(TransSalesEntry_L."Store No.", TransSalesEntry_L."POS Terminal No.", TransSalesEntry_L."Transaction No.") then
                            if (TransactionStatus_L.Status in [TransactionStatus_L.Status::"Items Posted", TransactionStatus_L.Status::Posted]) and
                                (TransactionStatus_L."Statement No." <> StatementNoIn) then
                                TransSalesLineAlreadyPosted := true;
                        if not TransSalesLineAlreadyPosted then
                            if ((TransSalesEntry_TEMP.Quantity > 0) and (TransSalesEntry_L.Quantity < 0)) or
                                ((TransSalesEntry_TEMP.Quantity < 0) and (TransSalesEntry_L.Quantity > 0)) then begin
                                ExplanationMsgFound := true;
                                if ExplanationMsgOut = '' then
                                    ExplanationMsgOut := StrSubstNo(ExplanationMsg, TransSalesEntry_TEMP."Item No.", TransSalesEntry_TEMP."Serial No.",
                                        TransSalesEntry_TEMP."Receipt No.", TransSalesEntry_L."Receipt No.")
                                else
                                    ExplanationMsgOut := '\' + StrSubstNo(ExplanationMsg, TransSalesEntry_TEMP."Item No.", TransSalesEntry_TEMP."Serial No.",
                                        TransSalesEntry_TEMP."Receipt No.", TransSalesEntry_L."Receipt No.");
                            end;
                    until TransSalesEntry_L.Next() = 0;
            until TransSalesEntry_TEMP.Next() = 0;
    end;

    local procedure OpenTablesBuffers()
    var
        TransactionStatus: Record "LSC Transaction Status";
        RecRef: RecordRef;
    begin
        RecRef.GETTABLE(TransactionStatus);
        IF BufferUtility.IsBufferOpen(RecRef, 1) THEN
            BufferUtility.CloseBuffer(RecRef, 1);
        BufferUtility.OpenBuffer(RecRef, 1);
    end;

    local procedure FlushTablesBuffers()
    var
        TransactionStatus: Record "LSC Transaction Status";
        TransSalesEntryStatus: Record "LSC Trans. Sales Entry Status";
        TransactionStatusTmp: Record "LSC Transaction Status" temporary;
        RecRef: RecordRef;
    begin
        OnBeforeFlushTablesBuffers();

        RecRef.GetTable(TransactionStatusTmp);
        BufferUtility.SetTableFilter(1, RecRef, 1);
        if BufferUtility.FindFirstRec(1, RecRef, 1) then
            repeat
                RecRef.SetTable(TransactionStatusTmp);
                TransactionStatus.Get(TransactionStatusTmp."Store No.", TransactionStatusTmp."POS Terminal No.", TransactionStatusTmp."Transaction No.");
                TransactionStatus.TransferFields(TransactionStatusTmp, FALSE);
                TransactionStatus.Modify(true);
                TransSalesEntryStatus.SetRange("Store No.", TransactionStatus."Store No.");
                TransSalesEntryStatus.SetRange("POS Terminal No.", TransactionStatus."POS Terminal No.");
                TransSalesEntryStatus.SetRange("Transaction No.", TransactionStatus."Transaction No.");
                TransSalesEntryStatus.ModifyAll(Status, TransactionStatus.Status, TRUE);
                SetTransInvAdjmtEntryStatus(TransactionStatus);
            until BufferUtility.NextRec(1, 1, RecRef, 1) = 0;
        RecRef.GETTABLE(TransactionStatusTmp);
        BufferUtility.CloseBuffer(RecRef, 1);
    end;

    local procedure TransStatusToBuffer(VAR TransactionStatus: Record "LSC Transaction Status")
    var
        RecRef: RecordRef;
    begin
        RecRef.GETTABLE(TransactionStatus);
        BufferUtility.UpdateRec(RecRef, 1);
    end;

    local procedure GetTransStatusBuffer(VAR TransactionStatusTmp_p: Record "LSC Transaction Status" TEMPORARY)
    var
        TransactionStatusTmp: Record "LSC Transaction Status" temporary;
        RecRef: RecordRef;
    begin
        RecRef.GETTABLE(TransactionStatusTmp);
        BufferUtility.SetTableFilter(1, RecRef, 1);
        IF BufferUtility.FindFirstRec(1, RecRef, 1) THEN
            REPEAT
                RecRef.SETTABLE(TransactionStatusTmp);
                TransactionStatusTmp_p.INIT();
                TransactionStatusTmp_p := TransactionStatusTmp;
                TransactionStatusTmp_p.INSERT();
            Until BufferUtility.NextRec(1, 1, RecRef, 1) = 0;
    end;

    procedure AddSourceCurrency(VAR GenJnlLine_l: Record "Gen. Journal Line")
    begin
        GenJnlLine_l."Source Currency Code" := GenJnlLine_l."Currency Code";
        GenJnlLine_l."Source Currency Amount" := GenJnlLine_l.Amount;
        GenJnlLine_l."Source Curr. VAT Base Amount" := GenJnlLine_l."VAT Base Amount";
        GenJnlLine_l."Source Curr. VAT Amount" := GenJnlLine_l."VAT Amount";
    end;

    local procedure GetItem(ItemNo: Code[20]; CallingRecord: Variant; var Item_p: Record Item)
    var
        IsHandled: Boolean;
    begin
        OnBeforeGetItem(ItemNo, CallingRecord, Item_p, IsHandled);
        if IsHandled then
            exit;

        Item_p.Get(ItemNo);

        OnAfterGetItem(ItemNo, CallingRecord, Item_p);
    end;

    procedure SetPreviewMode(NewPreviewMode: Boolean)
    begin
        PreviewMode := NewPreviewMode;
    end;

    //internal 
    procedure PostStatement(var StatementRec: Record "LSC Statement"; StoreRec: Record "LSC Store"; BatchPostingStatus: Text[30]; BatchPosting: Codeunit "LSC Batch Posting")
    begin
        if not ValidateStatement(StatementRec, BatchPostingStatus) then
            exit;
        //if Confirm(PostStatementQst, true) then begin
        StoreRec.Get(StatementRec."Store No.");
        if not StoreRec."Use Batch Posting for Statem." then
            Run(StatementRec)
        else
            BatchPosting.ValidateAndPostStatement(StatementRec, false);
        //end;
    end;

    internal procedure ValidateStatement(var StatementRec: Record "LSC Statement"; BatchPostingStatus: Text[30]): Boolean
    var
        ExplanationMsg: Text;
    begin
        if StatementRec.Recalculate then
            Error(StatementRecalculationWarningTxt);

        if not SafeManagementCheck(StatementRec) then
            exit(false);

        StatementRec.CalcFields("Serial/Lot No. Not Valid");
        if StatementRec."Serial/Lot No. Not Valid" > 0 then
            if CheckSerialNo(StatementRec."Store No.", StatementRec."No.", ExplanationMsg) then
                Message(ExplanationMsg);
        if StatementRec."Serial/Lot No. Not Valid" > 0 then
            Error(UnresolvedSerialNumbersMessageErr, StatementRec."Serial/Lot No. Not Valid");

        if BatchPostingStatus <> '' then
            Error(BatchPostingQueueStatusMessage);
        exit(true);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeStatementPost(var Statement: Record "LSC Statement"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeProcessTransactionStatus(var TransactionStatus: Record "LSC Transaction Status"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterProcessTransactionStatus(var TransactionStatus: Record "LSC Transaction Status"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeProcessStatementLine(var StatementLine: Record "LSC Statement Line"; Statement: Record "LSC Statement"; var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line"; var TotalSum: Decimal; var LineCounter: Integer; var Win: Dialog; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterProcessStatementLine(var StatementLine: Record "LSC Statement Line"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeProcessSafeStatementLine(var SafeStatementLine: Record "LSC Safe Statement Line"; Statement: Record "LSC Statement"; var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line"; var TotalSum: Decimal; var LineCounter: Integer; var Win: Dialog; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterProcessSafeStatementLine(var SafeStatementLine: Record "LSC Safe Statement Line"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeProcessGLedgerPostingBuffer(var PostingBuffer: Record "LSC Ledger Posting Buffer"; Statement: Record "LSC Statement"; var TempDimBufPost: Record "Dimension Buffer")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterProcessLedgerPostingBuffer(var PostingBuffer: Record "LSC Ledger Posting Buffer"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeProcessItemPostingBufferV2(var ItemPostingBuffer: Record "LSC Item Posting Buffer V2"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterProcessItemPostingBufferV2(var ItemPostingBuffer: Record "LSC Item Posting Buffer V2"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeEndProcessTransactionStatus(var TransactionStatus: Record "LSC Transaction Status"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeItemJnlLinePostLineV2(var ItemJournalLine: Record "Item Journal Line"; Statement: Record "LSC Statement"; var ItemPostingBuffer: Record "LSC Item Posting Buffer V2")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterItemJnlLinePostLine(var ItemJournalLine: Record "Item Journal Line"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterEndProcessTransactionStatus(var TransactionStatus: Record "LSC Transaction Status"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPostItemSales(var TransSalesEntry: Record "LSC Trans. Sales Entry"; TransactionHeader: Record "LSC Transaction Header"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeRunItemPosting(var Statement: Record "LSC Statement"; UndoItemPosting: Boolean; var IsHandled: Boolean; var locStatement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterRunItemPosting(var Statement: Record "LSC Statement"; UndoItemPosting: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostItemAdjustmentV2(var ItemPostingBuffer: Record "LSC Item Posting Buffer V2"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostItemV2(var ItemPostingBuffer: Record "LSC Item Posting Buffer V2"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostToCustomer(var Statement: Record "LSC Statement"; var TransactionHeader: Record "LSC Transaction Header"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPostToCustomer(var Statement: Record "LSC Statement"; var TransactionHeader: Record "LSC Transaction Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGenJnlPostLine(var GenJournalLine: Record "Gen. Journal Line"; var Statement: Record "LSC Statement"; var TransactionHeader: Record "LSC Transaction Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeMakeOrder(var TransSalesEntry: Record "LSC Trans. Sales Entry"; TransactionHeader: Record "LSC Transaction Header"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeModifySalesHeaderInMakeOrder(var SalesHeader: Record "Sales Header"; TransactionHeader: Record "LSC Transaction Header"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterMakeOrder(var SalesHeader: Record "Sales Header"; TransactionHeader: Record "LSC Transaction Header"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeUpdatePaymentBuffer(var PaymPostingBuffer: Record "LSC Ledger Posting Buffer" temporary; pAccountType: Enum "LSC Tender Posting Acc. Type"; pAccountNo: Code[20];
                                                                                                                                       pDescription: Text[50];
                                                                                                                                       pCurrencyCode: Code[10];
                                                                                                                                       pAmount: Decimal;
                                                                                                                                       pAmountLCY: Decimal; var BufferLineNo: Integer; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterStatementPost(var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateDocNo(var DocNo: Code[50]; StoreNo: Code[10]; POSTerminalNo: Code[10]; TransactionNo: Integer)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateDocNo(var DocNo: Code[50]; StoreNo: Code[10]; POSTerminalNo: Code[10]; TransactionNo: Integer)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeUpdateItemPostingBufferV2(var ItemPostingBuffer: Record "LSC Item Posting Buffer V2")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeInsertItemPostingBufferSalesV2(var ItemPostingBuffer: Record "LSC Item Posting Buffer V2"; var TransSalesEntry: Record "LSC Trans. Sales Entry"; var TransactionHeader: Record "LSC Transaction Header");
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeInsertBOMPostingBufferSales(var BOMPostingBuffer: Record "LSC BOM Posting Buffer"; var TransSalesEntry: Record "LSC Trans. Sales Entry");
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostNegAdjV2(var ItemPostingBuffer: Record "LSC Item Posting Buffer V2"; var TransInventoryEntry: Record "LSC Trans. Inventory Entry"; var TransactionHeader: Record "LSC Transaction Header");
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeRetailBOMJnlPostLine(var RetailBOMJnlLine: Record "LSC Retail BOM Journal Line"; var BOMPostingBuffer: Record "LSC BOM Posting Buffer");
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeRetailBOMJnlPostBOMCompLine(var RetailBOMJnlLine: Record "LSC Retail BOM Journal Line"; var Store: Record "LSC Store");
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCalculateRoundingDifference(var Statement: Record "LSC Statement"; var GenJnlLine: Record "Gen. Journal Line"; var TotalSum: Decimal)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeProcessLedgerPostingBuffer(var GenJnlLine: Record "Gen. Journal Line"; var PostingBuffer: Record "LSC Ledger Posting Buffer"; var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeSalesTaxCountryCheck(var SalesTaxCountry: Option US,CA,,,,,,,,,,,,NoTax; TaxArea: Record "Tax Area")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostIncomeExpLine(var TransIncomeExpenseEntry: Record "LSC Trans. Inc./Exp. Entry"; TransactionHeader: Record "LSC Transaction Header"; Statement: Record "LSC Statement"; DocNumber: Code[20]; var PostingBuffer: Record "LSC Ledger Posting Buffer" temporary; var Handled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostCustomerStatementLine(Statement: Record "LSC Statement"; var StatementLine: Record "LSC Statement Line"; var GenJnlLine: Record "Gen. Journal Line"; var TotalSum: Decimal; Store: Record "LSC Store"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGenJnlLineRunWithCheckInStatementPost(var GenJnlLine: Record "Gen. Journal Line"; var Transaction: Record "LSC Transaction Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeUpdLedgerPostingBufferInPostIncomeExpLine(var PostingBuffer: Record "LSC Ledger Posting Buffer")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterGetVATPostingSetup(var VATPostingSetup: Record "VAT Posting Setup"; var Transaction: Record "LSC Transaction Header"; var TransSalesEntry: Record "LSC Trans. Sales Entry"; var GenPostingSetup: Record "General Posting Setup")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeUpdLedgerPostingBufferInPostIncomeExpLine2(var PostingBuffer: Record "LSC Ledger Posting Buffer"; var TransIncomeExpenseEntry: Record "LSC Trans. Inc./Exp. Entry"; var TempDimBufPost: Record "Dimension Buffer" temporary)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindDimensions(var Statement: Record "LSC Statement"; var DimBuf: Record "Dimension Buffer"; var TempDimBufPost: Record "Dimension Buffer" temporary; var IsHandled: boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGetDefaultDim(var Statement: Record "LSC Statement"; var TableID: array[10] of Integer; var No: array[10] of Code[20]; var GlobalDim1Code: Code[20]; var GlobalDim2Code: Code[20]; var Len: Integer; var TransactionHeader: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry"; var IsHandled: boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeUpdLedgerPostingBufferInPostItemSales(var PostingBuffer: Record "LSC Ledger Posting Buffer"; var TransSalesEntry: Record "LSC Trans. Sales Entry"; Len: Integer; var PostingBufferArray: array[2] of Record "LSC Ledger Posting Buffer" temporary; VATFactor: Decimal; var TempDimBufNew: Record "Dimension Buffer" temporary; var TableID: array[10] of Integer; var No: array[10] of Code[20]; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterSalesLineModify(var SalesLine: Record "Sales Line"; var TransSalesEntry: Record "LSC Trans. Sales Entry"; TransIncomeExpenseEntry: Record "LSC Trans. Inc./Exp. Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnUpdateGnlSafeRefNo(var pGenJnlLine: Record "Gen. Journal Line"; pSafeStatementLine: Record "LSC Safe Statement Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeInsertPostedStatementLine(StatementLine: Record "LSC Statement Line"; var PostedStatementLine: Record "LSC Posted Statement Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostItemSale(var TransSalesEntry: Record "LSC Trans. Sales Entry"; TransactionHeader: Record "LSC Transaction Header";
                                        Statement: Record "LSC Statement"; var DocNumber: Code[20]; PostGLEntries: Boolean; var IsHandled: Boolean)
    begin
    end;

    procedure SafeManagementCheck(Statement_p: Record "LSC Statement") ProceedWithPosting: Boolean
    var
        Store_l: Record "LSC Store";
        Transaction_l: Record "LSC Transaction Header";
        Transaction2_l: Record "LSC Transaction Header";
        TransactionStatus_l: Record "LSC Transaction Status";
        StatementLine_l: Record "LSC Statement Line";
        SafeStatementLine_l: Record "LSC Safe Statement Line";
        POSTerminal_l: Record "LSC POS Terminal";
        StatementLineTemp: Record "LSC Statement Line" temporary;
        TmpEndOfDayEntry: Record "LSC POS Start Status" temporary;
        POSTerminalTemp: Record "LSC POS Terminal" temporary;
        StatementCalculate: Codeunit "LSC Statement-Calculate";
        IsMissingEndOfDay: Boolean;
        IsCheckEOD: Boolean;
        IsHandled: Boolean;
        StatementNotReadyMsg: Label 'This Statement is not ready to be posted due to missing End of Day Declaration.';
        PostingReadyMsg: Label 'Incomplete Transactions have been excluded from this Statement, please calculate them in a new Statement. This Statement is now ready for posting.';
        PostingNotReadyQst: Label 'Not all POS/Cashiers are ready for posting. Do you want to exclude the relevant Transactions from the Statement?';
    begin
        OnBeforeSafeManagementCheck(Statement_p, ProceedWithPosting, IsHandled);
        if IsHandled then
            exit(ProceedWithPosting);
        if Store_l.Get(Statement_p."Store No.") then
            if Store_l."Safe Mgnt. in Use" then begin
                if Statement_p."Closing Method" = Statement_p."Closing Method"::"Date and Time" then begin
                    Transaction_l.SetCurrentKey("Store No.", Date);
                    Transaction_l.SetRange("Store No.", Statement_p."Store No.");
                    Transaction_l.SetRange(Date, Statement_p."Trans. Starting Date", Statement_p."Trans. Ending Date");
                end else
                    if Statement_p."Closing Method" = Statement_p."Closing Method"::Shift then begin
                        Transaction_l.SetCurrentKey("Store No.", "Shift Date", "Shift No.");
                        Transaction_l.SetRange("Store No.", Statement_p."Store No.");
                        Transaction_l.SetRange("Shift Date", Statement_p."Shift Date");
                        Transaction_l.SetRange("Shift No.", Statement_p."Shift No.");
                    end;
                Transaction2_l.Copy(Transaction_l);
                Transaction_l.SetRange("Transaction Type", Transaction_l."Transaction Type"::"Tender Decl.");
                Transaction_l.SetRange("Entry Status", Transaction_l."Entry Status"::" ");
                Transaction_l.SetAutoCalcFields("Statement No.");
                if Transaction_l.FindSet() then
                    repeat
                        if Transaction_l."Statement No." = Statement_p."No." then
                            StatementCalculate.FindLastTenderDecl(Transaction_l, Store_l, Statement_p."No.");
                    until Transaction_l.Next() = 0;
                StatementCalculate.GetTenderDeclareEntries(TmpEndOfDayEntry);

                //Populate all POSes that require tender declaration
                POSTerminal_l.SetRange("Store No.", Store_l."No.");
                POSTerminal_l.SetRange("Exclude from Cash Mgnt.", false);
                if POSTerminal_l.FindSet() then
                    repeat
                        POSTerminalTemp := POSTerminal_l;
                        if POSTerminal_l."Terminal Statement" then
                            if POSTerminal_l."Statement Method" = Store_l."Statement Method" then
                                POSTerminalTemp."Terminal Statement" := false;
                        POSTerminalTemp.Insert();
                    until POSTerminal_l.Next() = 0;

                //Populate unique Staff/POS ID in Statement Lines
                StatementLine_l.SetRange("Statement No.", Statement_p."No.");
                if StatementLine_l.FindSet() then
                    repeat
                        StatementLineTemp.SetRange("Statement No.", StatementLine_l."Statement No.");
                        StatementLineTemp.SetRange("Statement Code", StatementLine_l."Statement Code");
                        StatementLineTemp.SetRange("Staff ID", StatementLine_l."Staff ID");
                        StatementLineTemp.SetRange("POS Terminal No.", StatementLine_l."POS Terminal No.");
                        if StatementLineTemp.IsEmpty() then begin
                            StatementLineTemp := StatementLine_l;
                            StatementLineTemp."Counting Required" := false; //Marker for release
                            StatementLineTemp.Insert();
                        end;
                    until StatementLine_l.Next() = 0;

                TransactionStatus_l.Reset();
                TransactionStatus_l.SetCurrentKey("Statement No.");
                TransactionStatus_l.SetRange("Statement No.", Statement_p."No.");
                TmpEndOfDayEntry.SetRange("Store No.", Statement_p."Store No.");
                IsMissingEndOfDay := false;
                StatementLineTemp.Reset();
                if StatementLineTemp.FindSet(true) then
                    repeat
                        IsCheckEOD := false;
                        POSTerminalTemp.Reset();

                        if (StatementLineTemp."POS Terminal No." = '') and (StatementLineTemp."Staff ID" = '') then begin
                            //Method::Total
                            TmpEndOfDayEntry.SetRange(Type, TmpEndOfDayEntry.Type::Staff);
                            if Store_l."Statement Method" <> Store_l."Statement Method"::Total then begin
                                POSTerminalTemp.SetRange("Terminal Statement", true);
                                POSTerminalTemp.SetRange("Statement Method", POSTerminalTemp."Statement Method"::Total);
                            end else
                                POSTerminalTemp.SetRange("Terminal Statement", false);
                            if POSTerminalTemp.FindSet() then
                                repeat
                                    TransactionStatus_l.SetRange("POS Terminal No.", POSTerminalTemp."No.");
                                    if not TransactionStatus_l.IsEmpty() then
                                        IsCheckEOD := true;
                                until (POSTerminalTemp.Next() = 0) or IsCheckEOD;
                        end else
                            if StatementLineTemp."Staff ID" <> '' then begin
                                //Method::Staff
                                TmpEndOfDayEntry.SetRange(Type, TmpEndOfDayEntry.Type::Staff);
                                if Store_l."Statement Method" <> Store_l."Statement Method"::Staff then begin
                                    POSTerminalTemp.SetRange("Terminal Statement", true);
                                    POSTerminalTemp.SetRange("Statement Method", POSTerminalTemp."Statement Method"::Staff);
                                end else
                                    POSTerminalTemp.SetRange("Terminal Statement", false);
                                if POSTerminalTemp.FindSet() then
                                    repeat
                                        TransactionStatus_l.SetRange("POS Terminal No.", POSTerminalTemp."No.");
                                        if TransactionStatus_l.FindSet() then
                                            repeat
                                                if Transaction_l.Get(Statement_p."Store No.", POSTerminalTemp."No.", TransactionStatus_l."Transaction No.") then
                                                    if StatementLineTemp."Statement Code" = Transaction_l."Staff ID" then
                                                        IsCheckEOD := true;
                                            until (TransactionStatus_l.Next() = 0) or IsCheckEOD;
                                    until (POSTerminalTemp.Next() = 0) or IsCheckEOD;
                            end else
                                if StatementLineTemp."POS Terminal No." <> '' then begin
                                    //Method::POS Terminal
                                    TmpEndOfDayEntry.SetRange(Type, TmpEndOfDayEntry.Type::"POS Terminal");
                                    if Store_l."Statement Method" <> Store_l."Statement Method"::"POS Terminal" then begin
                                        POSTerminalTemp.SetRange("Terminal Statement", true);
                                        POSTerminalTemp.SetRange("Statement Method", POSTerminalTemp."Statement Method"::"POS Terminal");
                                    end else
                                        POSTerminalTemp.SetRange("Terminal Statement", false);
                                    POSTerminalTemp.SetRange("No.", StatementLineTemp."Statement Code");
                                    if not POSTerminalTemp.IsEmpty() then
                                        IsCheckEOD := true;
                                end;

                        if IsCheckEOD then begin
                            TmpEndOfDayEntry.SetRange(Id, StatementLineTemp."Statement Code");
                            if TmpEndOfDayEntry.IsEmpty() then begin
                                IsMissingEndOfDay := true;
                                StatementLineTemp."Counting Required" := true;
                                StatementLineTemp.Modify();
                            end;
                        end;
                    until StatementLineTemp.Next() = 0;
                if IsMissingEndOfDay then begin
                    StatementLineTemp.Reset();
                    StatementLineTemp.SetRange("Counting Required", false);
                    if StatementLineTemp.IsEmpty() then begin
                        Message(StatementNotReadyMsg);
                        exit(false);
                    end;
                    if not GuiAllowed then
                        Error(Text002)
                    else
                        if not Confirm(PostingNotReadyQst) then
                            Error(Text002);
                    StatementLineTemp.Reset();
                    StatementLineTemp.SetRange("Counting Required", true);
                    Transaction2_l.SetAutoCalcFields("Statement No.");
                    if StatementLineTemp.FindSet() then
                        repeat
                            POSTerminalTemp.Reset();
                            if (StatementLineTemp."POS Terminal No." = '') and (StatementLineTemp."Staff ID" = '') then begin
                                //Method::Total
                                if Store_l."Statement Method" <> Store_l."Statement Method"::Total then begin
                                    POSTerminalTemp.SetRange("Terminal Statement", true);
                                    POSTerminalTemp.SetRange("Statement Method", POSTerminalTemp."Statement Method"::Total);
                                end else
                                    POSTerminalTemp.SetRange("Terminal Statement", false);
                                if Transaction2_l.FindSet() then
                                    repeat
                                        if (Transaction2_l."Statement No." = Statement_p."No.") then begin
                                            POSTerminalTemp.SetRange("No.", Transaction2_l."POS Terminal No.");
                                            if not POSTerminalTemp.IsEmpty() then
                                                ReleaseTransactions(Transaction2_l);
                                        end;
                                    until Transaction2_l.Next() = 0;
                            end else
                                if StatementLineTemp."Staff ID" <> '' then begin
                                    //Method::Staff
                                    if Store_l."Statement Method" <> Store_l."Statement Method"::Staff then begin
                                        POSTerminalTemp.SetRange("Terminal Statement", true);
                                        POSTerminalTemp.SetRange("Statement Method", POSTerminalTemp."Statement Method"::Staff);
                                    end else
                                        POSTerminalTemp.SetRange("Terminal Statement", false);
                                    if Transaction2_l.FindSet() then
                                        repeat
                                            if (Transaction2_l."Statement No." = Statement_p."No.") and (Transaction2_l."Staff ID" = StatementLineTemp."Staff ID") then begin
                                                POSTerminalTemp.SetRange("No.", Transaction2_l."POS Terminal No.");
                                                if not POSTerminalTemp.IsEmpty() then
                                                    ReleaseTransactions(Transaction2_l);
                                            end;
                                        until Transaction2_l.Next() = 0;
                                end else
                                    if StatementLineTemp."POS Terminal No." <> '' then begin
                                        //Method::POS Terminal
                                        if Store_l."Statement Method" <> Store_l."Statement Method"::"POS Terminal" then begin
                                            POSTerminalTemp.SetRange("Terminal Statement", true);
                                            POSTerminalTemp.SetRange("Statement Method", POSTerminalTemp."Statement Method"::"POS Terminal");
                                        end else
                                            POSTerminalTemp.SetRange("Terminal Statement", false);
                                        if Transaction2_l.FindSet() then
                                            repeat
                                                if (Transaction2_l."Statement No." = Statement_p."No.") and (Transaction2_l."POS Terminal No." = StatementLineTemp."POS Terminal No.") then begin
                                                    POSTerminalTemp.SetRange("No.", Transaction2_l."POS Terminal No.");
                                                    if not POSTerminalTemp.IsEmpty() then
                                                        ReleaseTransactions(Transaction2_l);
                                                end;
                                            until Transaction2_l.Next() = 0;
                                    end;
                            StatementLine_l.SetRange("Statement No.", StatementLineTemp."Statement No.");
                            StatementLine_l.SetRange("Statement Code", StatementLineTemp."Statement Code");
                            StatementLine_l.SetRange("Staff ID", StatementLineTemp."Staff ID");
                            StatementLine_l.SetRange("POS Terminal No.", StatementLineTemp."POS Terminal No.");
                            StatementLine_l.DeleteAll(true);
                            SafeStatementLine_l.SetRange("Statement No.", StatementLineTemp."Statement No.");
                            SafeStatementLine_l.SetRange("Statement Code", StatementLineTemp."Statement Code");
                            SafeStatementLine_l.SetRange("Staff ID", StatementLineTemp."Staff ID");
                            SafeStatementLine_l.SetRange("POS Terminal No.", StatementLineTemp."POS Terminal No.");
                            SafeStatementLine_l.DeleteAll(true);
                        until StatementLineTemp.Next() = 0;
                    Message(PostingReadyMsg);
                    exit(false);
                end;
            end;
        exit(true);
    end;

    local procedure ReleaseTransactions(TransactionHeader_p: Record "LSC Transaction Header")
    var
        TransactionStatus_l: Record "LSC Transaction Status";
        TransSalesEntryStatus_l: Record "LSC Trans. Sales Entry Status";
    begin
        if TransactionStatus_l.Get(TransactionHeader_p."Store No.", TransactionHeader_p."POS Terminal No.", TransactionHeader_p."Transaction No.") then begin
            TransactionStatus_l."Statement No." := '';
            TransactionStatus_l.Modify(true);
        end;
        TransSalesEntryStatus_l.Reset();
        TransSalesEntryStatus_l.SetRange("Store No.", TransactionHeader_p."Store No.");
        TransSalesEntryStatus_l.SetRange("POS Terminal No.", TransactionHeader_p."POS Terminal No.");
        TransSalesEntryStatus_l.SetRange("Transaction No.", TransactionHeader_p."Transaction No.");
        TransSalesEntryStatus_l.ModifyAll("Statement No.", '', true);
    end;

    local procedure ShowPostedConfirmationMessage(Statement: Record "LSC Statement")
    var
        OldStatement: Record "LSC Statement";
        PostedStatementDoc: Record "LSC Posted Statement";
        InstructionMgt: Codeunit "Instruction Mgt.";
        OpenPostedStatementQst: Label 'The %1 is posted as number %2 and moved to the Posted Statements window.\\Do you want to open the posted statement?', Comment = '%1= posted document type, %2 = posted document number';
    begin
        if not OldStatement.Get(Statement."Store No.", Statement."No.") then begin
            if PostedStatementDoc.Get(Statement."Posting No.") then
                if InstructionMgt.ShowConfirm(StrSubstNo(OpenPostedStatementQst, Statement.TableCaption, PostedStatementDoc."No."),
                 InstructionMgt.ShowPostedConfirmationMessageCode())
            then
                    Page.Run(Page::"LSC Posted Statement", PostedStatementDoc);
        end;
    end;

    local procedure TranferfieldsFromSafeStatementLine(var PostedSafeStatementLine: Record "LSC Posted Safe Statement Line"; SafeStatementLine: Record "LSC Safe Statement Line")
    begin
        PostedSafeStatementLine.Validate("Line No.", SafeStatementLine."Line No.");
        PostedSafeStatementLine.Validate("Statement Code", SafeStatementLine."Statement Code");
        PostedSafeStatementLine.Validate("Staff ID", SafeStatementLine."Staff ID");
        PostedSafeStatementLine.Validate("Transaction Type", SafeStatementLine."Transaction Type");
        PostedSafeStatementLine.Validate("POS Terminal No.", SafeStatementLine."POS Terminal No.");
        PostedSafeStatementLine.Validate("Bank Bag No.", SafeStatementLine."Bag No.");
        PostedSafeStatementLine.Validate("Tender Type", SafeStatementLine."Tender Type");
        PostedSafeStatementLine.Validate("Currency Code", SafeStatementLine."Currency Code");
        PostedSafeStatementLine.Validate(Amount, SafeStatementLine.Amount);
        PostedSafeStatementLine.Validate("Amount in LCY", SafeStatementLine."Amount in LCY");
        PostedSafeStatementLine.Validate("Real Exchange Rate", SafeStatementLine."Real Exchange Rate");
        PostedSafeStatementLine.Validate("Posted Date", SafeStatementLine."Posted Date");
#pragma warning disable AL0432
        PostedSafeStatementLine.Validate(Description, SafeStatementLine.Description);
#pragma warning restore AL0432
        PostedSafeStatementLine.Validate("Trans. Amount in LCY", SafeStatementLine."Trans. Amount in LCY");
        PostedSafeStatementLine.Validate("Trans. Amount", SafeStatementLine."Trans. Amount");
        PostedSafeStatementLine.Validate("Difference in LCY", SafeStatementLine."Difference in LCY");
        PostedSafeStatementLine.Validate("Difference Amount", SafeStatementLine."Difference Amount");
        PostedSafeStatementLine.Validate("Store No.", SafeStatementLine."Store No.");
        PostedSafeStatementLine.Validate("Replication Counter", SafeStatementLine."Replication Counter");
        PostedSafeStatementLine.Validate("Bal. Account Type", SafeStatementLine."Bal. Account Type");
        PostedSafeStatementLine.Validate("Bal. Account No.", SafeStatementLine."Bal. Account No.");
        PostedSafeStatementLine.Validate(BalAccountName, SafeStatementLine."Bal. Account Name");
        PostedSafeStatementLine.Validate("Tender Type Card No.", SafeStatementLine."Tender Type Card No.");
        SafeStatementLine.CalcFields("Tender Type Name");
        PostedSafeStatementLine."Tender Type Name" := SafeStatementLine."Tender Type Name";
    end;

    local procedure CreateInitialGenJnlLine(Rec: Record "LSC Statement"; var GenJnlLine: Record "Gen. Journal Line"; AccountType: Enum "Gen. Journal Account Type"; AccountNo: Code[20]; Description: Text; Amount_p: Decimal)
    begin
        Clear(GenJnlLine);
        GenJnlLine.Init();
        GenJnlLine."Account Type" := AccountType;
        GenJnlLine."Posting Date" := Rec."Posting Date";
        GenJnlLine."Document Date" := Rec."Posting Date";
        GenJnlLine."Document Type" := GenJnlLine."Document Type"::" ";
        GenJnlLine."Document No." := Rec."Posting No.";
        GenJnlLine."LSC Statement No." := Rec."Posting No.";
        GenJnlLine."External Document No." := Rec."Posting No.";
        GenJnlLine.Validate("Account No.", AccountNo);
        GenJnlLine.Description := CopyStr(Description, 1, MaxStrLen(GenJnlLine.Description));
        GenJnlLine."System-Created Entry" := true;
        GenJnlLine.Amount := Amount_p;
        OnAfterCreateInitialGenJnlLine(Rec, GenJnlLine, AccountType, AccountNo, Description, Amount_p);
    end;

    internal procedure FindAndMarkStatementNoInPrepaymentInvoiceGLEAndCLE(CustomerOrderID: Code[20]; StatementNo: Code[20])
    var
        CLEntries: record "Cust. Ledger Entry";
        GLEntries: Record "G/L Entry";
    begin
        //!!!
        if COPrepaymentInvoiceMan.IsCustomerOrderPrepaymentInvoiceMarked(CustomerOrderID) then begin
            CLEntries.SetRange("LSC Statement No.", '');
            CLEntries.SetRange("LSC Customer Order ID", CustomerOrderID);
            CLEntries.ModifyAll("LSC Statement No.", StatementNo);

            GLEntries.SetRange("External Document No.", '');
            GLEntries.SetRange("LSC Customer Order ID", CustomerOrderID);
            GLEntries.ModifyAll("External Document No.", StatementNo);
        end;

    end;

    // Internal in 18.4
    procedure PublicSetRunningFromBatchPosting()
    begin
        SetRunningFromBatchPosting();
    end;

    // Internal in 18.4
    procedure PublicRunItemPosting(locStatement: Record "LSC Statement"; UndoItemPosting: Boolean)
    begin
        RunItemPosting(locStatement, UndoItemPosting);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeModifySalesLine(var SalesLine: Record "Sales Line"; TransactionHeader: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry"; TransIncomeExpenseEntry: Record "LSC Trans. Inc./Exp. Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    internal procedure OnBeforeCheckDifference(Statement: Record "LSC Statement"; Store: Record "LSC Store"; RunningFromBatchPosting: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeDeleteStatement(var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterStatementPostBeforeCommit(var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterInitSalesHeader(TransactionHeader: Record "LSC Transaction Header"; var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGetItem(ItemNo: Code[20]; CallingRecord: Variant; var Item: Record Item; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterGetItem(ItemNo: Code[20]; CallingRecord: Variant; var Item: Record Item)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostBOMOnRun(var BOMPostingBuffer: Record "LSC BOM Posting Buffer" temporary; StatementNo: Code[20]; var IsHandled: Boolean);
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeRetailBOMJnlPostLineRunWithCheck(var RetailBOMJnlLine: Record "LSC Retail BOM Journal Line"; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterSetAmountToPostToCustomer(Transaction: Record "LSC Transaction Header"; var AmountToPost: Decimal)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnPostDiscountBuffering_OnAfterGetDefaultDim(Transaction: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry"; var TempDimBufNew: Record "Dimension Buffer" temporary; var GlobalDimension1Code: Code[20]; var GlobalDimension2Code: Code[20])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateDiscBufferInPostItemSalesV2(var ItemPostingBuffer: array[2] of Record "LSC Item Posting Buffer V2" temporary; Transaction: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateBOMJnlLineDim(var RetailBOMJnlLine: Record "LSC Retail BOM Journal Line"; pSalesType: Code[20]; Transaction: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateGenJnlLineDim(var GenJnlLine: Record "Gen. Journal Line"; pSalesType: Code[20]; Transaction: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateItemJnlLineDim(var ItemJnlLine: Record "Item Journal Line"; var ItemPostingBuffer: Record "LSC Item Posting Buffer V2" temporary; var TempDimBufPost: Record "Dimension Buffer" temporary; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateItemJnlLineDim(var ItemJnlLine: Record "Item Journal Line"; pSalesType: Code[20]; Transaction: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterGetDefaultDimInPostItemSales(var SalesTypeCode: Code[20]; var GlobalDimension1Code: Code[20]; var GlobalDimension2Code: Code[20]; var TempDimBufNew: Record "Dimension Buffer" temporary; TransactionHeader: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckBlockedCustOfCustItemChecks(Statement_p: Record "LSC Statement"; CheckBlockedCustomer: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    internal procedure OnBeforeCheckCountedAmount(var CountedAmtChecked: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    internal procedure OnBeforeConfirmDifference(var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPostStatement(var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeItemPostingBufferModifyInCompressItemPostingBufferV2(var ItemPostingBufferAux: Record "LSC Item Posting Buffer V2"; var ItemPostingBuffer_2: Record "LSC Item Posting Buffer V2" temporary)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeItemPostingBufferModifyInSumItemPostingBufferV2(SumToIndex: Integer; var ItemPostingBuffer: array[2] of Record "LSC Item Posting Buffer V2" temporary; Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeRevertSignCurrDiscBufferInPostItemSalesV2(var ItemPostingBuffer: Record "LSC Item Posting Buffer V2")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGenJnlLineRunWithCheckPostSafeLine1(var GenJnlLine: Record "Gen. Journal Line"; var SafeStatementLine: Record "LSC Safe Statement Line"; var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGenJnlLineRunWithCheckPostSafeLine2(var GenJnlLine: Record "Gen. Journal Line"; var SafeStatementLine: Record "LSC Safe Statement Line"; var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGenJnlLineRunWithCheckPostSafeLine3(var GenJnlLine: Record "Gen. Journal Line"; var SafeStatementLine: Record "LSC Safe Statement Line"; var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGenJnlLineRunWithCheckPostSafeLine4(var GenJnlLine: Record "Gen. Journal Line"; var SafeStatementLine: Record "LSC Safe Statement Line"; var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGenJnlLineRunWithCheckPostSafeLine5(var GenJnlLine: Record "Gen. Journal Line"; var SafeStatementLine: Record "LSC Safe Statement Line"; var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGenJnlLineRunWithCheckPostSafeLine6(var GenJnlLine: Record "Gen. Journal Line"; var SafeStatementLine: Record "LSC Safe Statement Line"; var Statement: Record "LSC Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFlushTablesBuffers()
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeValidateSalesHeaderLocationAndDims(var SalesHeader: Record "Sales Header"; Store: Record "LSC Store"; var SkipLocAndDimsValidation: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostSalesOrderInMakeOrder(SalesHeader: Record "Sales Header")
    begin
    end;


    [IntegrationEvent(false, false)]
    local procedure OnBeforeInsertPostedSafeStatementLine(var PostedSafeStatementLine: Record "LSC Posted Safe Statement Line"; var SafeStatementLine: Record "LSC Safe Statement Line"; var Statement: record "LSC Statement"; var PostedStatement: Record "LSC Posted Statement")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterSafeStatementAccountSelection(var SafeStatementLine: Record "LSC Safe Statement Line"; var AccType: Enum "LSC Tender Posting Acc. Type"; var GLAccountNumber: Code[20]; var BankAccNo: Code[20])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnProcessGLedgerPostingBufferAfterInitGenJnlLine(Statement: Record "LSC Statement"; var GenJnlLine: Record "Gen. Journal Line"; PostingBuffer: Record "LSC Ledger Posting Buffer" temporary)
    begin
    end;

    [IntegrationEvent(true, false)]
    local procedure OnAfterDeletePostingBufferV2(var Statement: Record "LSC Statement"; var GenJnlLine: Record "Gen. Journal Line"; var TempDimBufNew: Record "Dimension Buffer" temporary; var TotalSum: Decimal; var Win: dialog; var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterInitLedgerPostingBufferPostItemSales(var PostingBuffer: Record "LSC Ledger Posting Buffer"; TransSalesEntry: Record "LSC Trans. Sales Entry"; Transaction: Record "LSC Transaction Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCalculatePostingBufferVatAmountsV2(var PostingBuffer: Record "LSC Ledger Posting Buffer"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(true, false)]
    [Obsolete('This event is obsolete. Use OnBeforePostDiscountLedgerBuffering2 instead.', '26.0')]
    local procedure OnBeforePostDiscountLedgerBuffering(var PostingBuffer: Record "LSC Ledger Posting Buffer"; GenPostingSetup: Record "General Posting Setup"; Len: Integer; Item: Record Item; Store: Record "LSC Store"; BackOfficeSetup: Record "LSC Retail Setup"; var TempDimBufNew: Record "Dimension Buffer" temporary; var TableID: array[10] of Integer; var No: array[10] of Code[20]; DiscAmount: Decimal; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeModifyLedgerPostingBufferInPostIncomeExpLine2(var PostingBuffer: Record "LSC Ledger Posting Buffer"; TransIncomeExpenseEntry: Record "LSC Trans. Inc./Exp. Entry"; Transaction: Record "LSC Transaction Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeMakeOrderValidateSellToCustomerSalesHeader(var SalesHeader: Record "Sales Header"; Transaction: Record "LSC Transaction Header"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnMakeOrderBeforeValidateQuantities(var SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header"; TransSalesEntry: Record "LSC Trans. Sales Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnMakeOrderBeforeValidateQuantities2(var SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header"; TransIncomeExpenseEntry: Record "LSC Trans. Inc./Exp. Entry")
    begin
    end;

    [IntegrationEvent(true, false)]
    local procedure OnBeforeUpdLedgerPostingBuffer(var PostingBuffer: Record "LSC Ledger Posting Buffer"; Statement: Record "LSC Statement"; Transaction: Record "LSC Transaction Header"; GenJnlLine: Record "Gen. Journal Line"; var TempDimBufNew: Record "Dimension Buffer" temporary; var TableID: array[10] of Integer; var No: array[10] of Code[20]; Currency: Record Currency)
    begin
    end;

    [IntegrationEvent(false, false)]
    internal procedure OnAfterPrePostingChecks(var Statement: Record "LSC Statement"; RunningFromBatchPosting_p: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGetDefaultDimInPostItemSales(Transaction: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry"; var TableID: array[10] of Integer; var No: array[10] of Code[20]; var Len: Integer)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterApplyGenJnlLine_PostPaymentToCustomer(var GenJnlLine: Record "Gen. Journal Line"; Transaction: Record "LSC Transaction Header"; DocNumber: Code[20]; SellToCustNo: Code[20]; TotalAmountPaid: Decimal; AppliesToDocNo: Code[20])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterProcessSafeStatementLines(Statement: Record "LSC Statement"; var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line"; var TotalSum: Decimal)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterAssignDocumentTypeInMakeOrder(var LSCTransactionHeader: Record "LSC Transaction Header"; var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckPostSalesHeader(var LSCTransactionHeader: Record "LSC Transaction Header"; var SalesHeader: Record "Sales Header"; var SkipPostSalesHeader: Boolean; PreviewMode: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckPostTransactionAsShipment(var LSCTransactionHeader: Record "LSC Transaction Header"; var PostTransactionAsShipment: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCLEPosting(var LSCTransactionHeader: Record "LSC Transaction Header"; var SkipCLEPosting: Boolean; var AmountToPost: Decimal; var GenJournlDocumentType: Enum "Gen. Journal Document Type")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateServItemOnTransSalesEnt(TransactionHeader: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry"; StatementNo: Code[20]; var TransSalesEntryStatus: Record "LSC Trans. Sales Entry Status"; Item: Record "Item"; var ItemPostingBuffer: Record "LSC Item Posting Buffer V2"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeUpdatePostingBufferSalesEntry(var PostingBuffer: Record "LSC Ledger Posting Buffer" temporary; OriginalTransSalesEntry: Record "LSC Trans. Sales Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeUpdatePostingBufferPaymentEntry(var PostingBuffer: Record "LSC Ledger Posting Buffer" temporary; OriginalTransSalesEntry: Record "LSC Trans. Sales Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterInsertDefaultDimensionBuffer(var TempDimBufNew: Record "Dimension Buffer" temporary; TransactionHeader: Record "LSC Transaction Header"; TransSalesEntry: Record "LSC Trans. Sales Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateInitialGenJnlLine(Rec: Record "LSC Statement"; var GenJnlLine: Record "Gen. Journal Line"; AccountType: Enum "Gen. Journal Account Type"; AccountNo: Code[20]; Description: Text; Amount: Decimal)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeUpdLedgerPostingBufferForCOFinalAmountPrepaymentInvoice(arg: Variant)
    begin
    end;

    [IntegrationEvent(true, false)]
    local procedure OnBeforePostDataEntryReverseVAT(DocNumber: Code[20]; Statement: Record "LSC Statement"; Transaction: Record "LSC Transaction Header"; TransInfocodeEntry: Record "LSC Trans. Infocode Entry"; var ItemPostingBuffer: Record "LSC Item Posting Buffer V2" temporary; var PostingBuffer: Record "LSC Ledger Posting Buffer"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(true, false)]
    local procedure OnBeforePostDiscountLedgerBuffering2(var PostingBuffer: array[2] of Record "LSC Ledger Posting Buffer"; GenPostingSetup: Record "General Posting Setup"; Len: Integer; Item: Record Item; Store: Record "LSC Store"; BackOfficeSetup: Record "LSC Retail Setup"; var TempDimBufNew: Record "Dimension Buffer" temporary; var TableID: array[10] of Integer; var No: array[10] of Code[20]; DiscAmount: Decimal; TransSalesEntry: Record "LSC Trans. Sales Entry"; DiscVATAmount: Decimal; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(true, false)]
    local procedure OnBeforePostItemInventory(OriginalTransSalesEntry: Record "LSC Trans. Sales Entry"; Item: Record Item; TransactionHeader: Record "LSC Transaction Header"; Statement: Record "LSC Statement"; DocNumber: Code[20]; var ItemPostingBuffer: Record "LSC Item Posting Buffer V2"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostTenderTypeStatementLine(TenderType: Record "LSC Tender Type"; StatementLine: Record "LSC Statement Line"; Store: Record "LSC Store"; GLAccountNumber: Code[20]; var TotalSum: Decimal; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCompressItemPostingBuffer(var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCLESkip(AmountToPost: Decimal; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeSafeManagementCheck(Statement: Record "LSC Statement"; var ProceedWithPosting: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeMakeOrderChecks(Statement: Record "LSC Statement"; TransactionHeader: Record "LSC Transaction Header"; var TransDiscountEntryTemp: Record "LSC Trans. Discount Entry" temporary; PostGLEntries: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterUpdatePaymentBuffer(var PaymPostingBuffer: Record "LSC Ledger Posting Buffer" temporary)
    begin
    end;
}