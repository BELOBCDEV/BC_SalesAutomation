page 68810 BMGTransSalesLotModifier
{
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Administration;
    Caption = 'Trans. Sales Lot Modifier';

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';

                field(Date; pDate)
                {
                    ApplicationArea = All;
                    Caption = 'Date';
                }
                field("Store No."; pStoreNo)
                {
                    ApplicationArea = All;
                    Caption = 'Store No.';
                    TableRelation = "LSC Store"."No.";

                    trigger OnValidate()
                    begin
                        UpdateItemHistoryFilter();
                        CurrPage.Update(false);
                    end;
                }
                field("Item No."; pItemNo)
                {
                    ApplicationArea = All;
                    Caption = 'Item No.';
                    TableRelation = Item."No.";
                    trigger OnValidate()
                    begin
                        UpdateItemHistoryFilter();
                        CurrPage.Update(false);
                    end;
                }
                field("Lot No."; pLotNo)
                {
                    ApplicationArea = All;
                    Caption = 'Lot No.';
                }
            }
            part(ItemHistoryPart; BMGItemLedgerEntriesPart)
            {
                ApplicationArea = All;
                Caption = 'Item History';
            }
            group(TransactionStatus)
            {
                Caption = 'Transaction Status';

                field("Store No. 2"; pTxnStoreNo)
                {
                    ApplicationArea = All;
                    Caption = 'Store No.';
                    TableRelation = "LSC Store"."No.";

                }
                field("POS Terminal No."; pPOSTerminalNo)
                {
                    ApplicationArea = All;
                    Caption = 'POS Terminal No.';
                }
                field("Transaction No."; pTransactionNo)
                {
                    ApplicationArea = All;
                    Caption = 'Transaction No.';
                }

            }
            group(Statement)
            {
                Caption = 'Open Statement';
                field("Statement No."; pStatementNo)
                {
                    ApplicationArea = All;
                    Caption = 'Statement No.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(UpdateLotNo)
            {
                ApplicationArea = All;
                Caption = 'Update Lot No.';
                Image = Edit;

                trigger OnAction()
                var
                    recTransSalesEntry: Record "LSC Trans. Sales Entry";
                    UpdateCount: Integer;
                begin
                    if pDate = 0D then
                        Error('Please enter a Date.');
                    if pStoreNo = '' then
                        Error('Please enter a Store No.');
                    if pItemNo = '' then
                        Error('Please enter an Item No.');
                    if pLotNo = '' then
                        Error('Please enter the new Lot No.');

                    recTransSalesEntry.Reset();
                    recTransSalesEntry.SetRange(Date, pDate);
                    recTransSalesEntry.SetRange("Store No.", pStoreNo);
                    recTransSalesEntry.SetRange("Item No.", pItemNo);

                    if not recTransSalesEntry.FindSet(true) then begin
                        Message('No Trans. Sales Entry records found for the given filters.');
                        exit;
                    end;

                    if not Confirm('Update Lot No. to "%1" for all matching Trans. Sales Entry records?', false, pLotNo) then
                        exit;

                    repeat
                        recTransSalesEntry."Original Lot No." := recTransSalesEntry."Lot No.";
                        recTransSalesEntry."Lot No." := pLotNo;
                        recTransSalesEntry.Modify();
                        UpdateCount += 1;
                    until recTransSalesEntry.Next() = 0;

                    Message('%1 record(s) updated successfully.', UpdateCount);
                end;
            }
            action(ClearSerialLotNotValid)
            {
                ApplicationArea = All;
                Caption = 'Clear Serial/Lot Not Valid';
                Image = ResetStatus;

                trigger OnAction()
                var
                    recTransStatus: Record "LSC Transaction Status";
                    UpdateCount: Integer;
                begin
                    if pTxnStoreNo = '' then
                        Error('Please enter a Store No. in the Transaction Status group.');

                    recTransStatus.Reset();
                    recTransStatus.SetRange("Store No.", pTxnStoreNo);
                    if pPOSTerminalNo <> '' then
                        recTransStatus.SetRange("POS Terminal No.", pPOSTerminalNo);
                    if pTransactionNo <> 0 then
                        recTransStatus.SetRange("Transaction No.", pTransactionNo);

                    if not recTransStatus.FindSet(true) then begin
                        Message('No Transaction Status records found for the given filters.');
                        exit;
                    end;

                    if not Confirm('Clear "Serial/Lot No. Not Valid" for all matching Transaction Status records?', false) then
                        exit;

                    repeat
                        recTransStatus."Serial/Lot No. Not Valid" := 0;
                        recTransStatus.Modify();
                        UpdateCount += 1;
                    until recTransStatus.Next() = 0;

                    Message('%1 Transaction Status record(s) updated successfully.', UpdateCount);
                end;
            }
            action(DoNotRecalcStatement)
            {
                ApplicationArea = All;
                Caption = 'Skip Recalc. Statement';
                Image = ResetStatus;

                trigger OnAction()
                var
                    LSCStatement: Record "LSC Statement";
                    UpdateCount: Integer;
                begin
                    LSCStatement.Reset();
                    LSCStatement.SetRange("No.", pStatementNo);
                    if LSCStatement.FindFirst() then begin
                        LSCStatement.Recalculate := false;
                        LSCStatement.Modify();
                        UpdateCount += 1;
                    end;
                    Message('%1 Open Statement record(s) updated successfully.', UpdateCount);
                end;

            }
        }
        area(Promoted)
        {
            actionref(UpdateLotNo_Promoted; UpdateLotNo) { }
            actionref(ClearSerialLotNotValid_Promoted; ClearSerialLotNotValid) { }
            actionref(DoNotRecalStatement_Promoted; DoNotRecalcStatement) { }
        }
    }

    local procedure UpdateItemHistoryFilter()
    begin
        CurrPage.ItemHistoryPart.Page.SetItemFilter(pItemNo, pStoreNo);
    end;

    var
        pDate: Date;
        pStoreNo: Code[20];
        pItemNo: Code[20];
        pLotNo: Code[50];
        pTxnStoreNo: Code[20];
        pPOSTerminalNo: Code[20];
        pTransactionNo: Integer;
        pStatementNo: Code[20];
}
