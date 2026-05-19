pageextension 68803 BMGSerialLotNoNotValidExt extends "LSC Serial/Lot No. Not Valid"
{
    layout
    {
        // Add changes to page layout here


    }



    actions
    {
        // Add changes to page actions here
        addafter("&Correct Serial/Lot No.")
        {
            action(CheckAvailableLotNo)
            {
                Caption = 'Assign Available Lot No.';
                ApplicationArea = All;
                trigger OnAction()
                var
                    ItemLedgerEntry: Record "Item Ledger Entry";
                    recStore: Record "LSC Store";
                    recItemJournalLine: Record "Item Journal Line";
                    recLSCTransStatus: Record "LSC Transaction Status";
                    recItemLedgEntry: Record "Item Ledger Entry" temporary;
                    recLSCTransSales: Record "LSC Trans. Sales Entry";
                    codItemReclassMgt: Codeunit BMGItemReclassMgt;
                    Text001: Label 'There are no Lot No.s available for Item %1 at Location %2.';
                    codDocumentNo: Code[20];
                    txtStorePref: text[2];
                    intItemWithNoLotCount: Integer;
                begin
                    recLSCTransSales.Reset();
                    recLSCTransSales.SetRange("Trans. Date", WorkDate());
                    recLSCTransSales.SetRange("Store No.", Rec."Store No.");
                    recLSCTransSales.SetFilter("Serial/Lot No. Not Valid", '<>0');

                    //Message('Record count is %1', recLSCTransSales.Count);
                    intItemWithNoLotCount := 0;

                    if recLSCTransSales.FindFirst() then
                        repeat
                            ItemLedgerEntry.Reset;
                            ItemLedgerEntry.SetCurrentKey("Item No.", Open, "Variant Code", Positive, "Location Code",
                              "Posting Date", "Expiration Date", "Lot No.", "Serial No.");

                            ItemLedgerEntry.SetRange("Item No.", recLSCTransSales."Item No.");
                            ItemLedgerEntry.SetRange(Open, true);
                            ItemLedgerEntry.SetRange(Positive, true);
                            ItemLedgerEntry.SetRange("Location Code", recLSCTransSales."Store No.");
                            ItemLedgerEntry.SetFilter("Lot No.", '<>%1&<>%2', '', recLSCTransSales."Lot No.");

                            if not ItemLedgerEntry.FindFirst() then
                                intItemWithNoLotCount += 1;

                            ItemLedgerEntry.SetFilter("Remaining Quantity", '>%1', ABS(recLSCTransSales.Quantity));
                            ItemLedgerEntry.SetRange("Reserved Quantity", 0);
                            ItemLedgerEntry.SetFilter("Entry Type", '<>%1', ItemLedgerEntry."Entry Type"::Sale);


                            if ItemLedgerEntry.FindFirst() then begin
                                recStore.Reset();
                                recStore.SetRange("No.", Rec."Store No.");
                                if recStore.FindFirst() then
                                    txtStorePref := recStore."Reclass Doc. Prefix";
                                codDocumentNo := txtStorePref + Format(WorkDate(), 0, '<month, 2><day, 2><year>');

                                //Message('Item No. %1', recLSCTransSales."Item No.");
                                recLSCTransSales."Serial/Lot No. Not Valid" := false;
                                recLSCTransSales."Original Lot No." := recLSCTransSales."Lot No.";
                                recLSCTransSales."Lot No." := ItemLedgerEntry."Lot No.";
                                recLSCTransSales.Modify();

                                recLSCTransStatus.Reset();
                                recLSCTransStatus.SetRange("Store No.", recLSCTransSales."Store No.");
                                recLSCTransStatus.SetRange("POS Terminal No.", recLSCTransSales."POS Terminal No.");
                                recLSCTransStatus.SetRange("Transaction No.", recLSCTransSales."Transaction No.");

                                if recLSCTransStatus.FindFirst() then begin
                                    recLSCTransStatus."Serial/Lot No. Not Valid" := recLSCTransStatus."Serial/Lot No. Not Valid" - 1;
                                    recLSCTransStatus.Modify();
                                end;
                            end;
                        until recLSCTransSales.Next() = 0;

                    //Message('%1 items with no Lot Nos. at Location %2', intItemWithNoLotCount, Rec."Store No.");
                    /*
                    recItemJournalLine.Reset();
                    recItemJournalLine.SetRange("Journal Template Name", 'TRANSFER');
                    recItemJournalLine.SetRange("Journal Batch Name", 'DEFAULT');

                    if recItemJournalLine.FindFirst() then
                        recItemJournalLine.DeleteAll();

                    codItemReclassMgt.CreateItemReclass('DEFAULT', codDocumentNo, Rec."Item No.", ItemLedgerEntry."Location Code", ABS(Rec.Quantity), Rec."Lot No.");
                    Clear(codItemReclassMgt);
                    */
                end;

            }

        }
    }

    procedure GetCurrentStoreNo(pcodStore: Code[10])
    var
    begin
        codStoreNo := pcodStore;
    end;

    var
        myInt: Integer;
        codStoreNo: Code[10];
}