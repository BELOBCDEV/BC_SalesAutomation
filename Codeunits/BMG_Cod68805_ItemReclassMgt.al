codeunit 68805 BMGItemReclassMgt
{
    trigger OnRun()
    begin

    end;

    procedure CreateItemReclass(pJournalBatchName: Code[10]; pDocNo: Code[20]; pcodItemNo: Code[20]; pLocationCode: Code[10]; pQuantity: Decimal; pLotNo: Code[50])
    var
        recItemJournalLine: Record "Item Journal Line";
        recReservationEntry: Record "Reservation Entry";
        codItemJnlPost: Codeunit "Item Jnl.-Post";
    begin
        recItemJournalLine.Init();
        recItemJournalLine."Journal Template Name" := 'TRANSFER';
        recItemJournalLine."Line No." := 10000;
        recItemJournalLine.Validate("Posting Date", WorkDate());
        recItemJournalLine."Document No." := pDocNo;
        recItemJournalLine.Validate("Item No.", pcodItemNo);
        recItemJournalLine."Entry Type" := recItemJournalLine."Entry Type"::Transfer;
        recItemJournalLine.Validate("Location Code", pLocationCode);
        recItemJournalLine.Validate(Quantity, pQuantity);
        recItemJournalLine."Journal Batch Name" := pJournalBatchName;
        recItemJournalLine."Source Code" := 'RECLASSJNL';
        recItemJournalLine.Insert();

        recReservationEntry.Reset();
        recReservationEntry.Init();
        recReservationEntry."Entry No." := GetLastNo();
        recReservationEntry."Item No." := pcodItemNo;
        recReservationEntry."Location Code" := pLocationCode;
        recReservationEntry."Quantity (Base)" := -pQuantity;
        recReservationEntry."Reservation Status" := recReservationEntry."Reservation Status"::Prospect;
        recReservationEntry."Creation Date" := WorkDate();
        recReservationEntry."Source Type" := 83;
        recReservationEntry."Source Subtype" := 4;
        recReservationEntry."Source ID" := 'TRANSFER';
        recReservationEntry."Source Batch Name" := pJournalBatchName;
        recReservationEntry."Source Ref. No." := 10000;
        recReservationEntry."Shipment Date" := WorkDate();
        recReservationEntry."Created By" := UserId;
        recReservationEntry."Qty. per Unit of Measure" := 1;
        recReservationEntry.Quantity := -pQuantity;
        recReservationEntry."Qty. to Handle (Base)" := -pQuantity;
        recReservationEntry."Qty. to Invoice (Base)" := -pQuantity;
        recReservationEntry.Validate("Lot No.", pLotNo);
        recReservationEntry.Validate("New Lot No.", pLotNo + '*');
        //recReservationEntry."Expiration Date" := WorkDate() + 365;
        if recReservationEntry."Expiration Date" <> 0D then
            recReservationEntry."New Expiration Date" := recReservationEntry."Expiration Date" + 365
        else
            recReservationEntry."New Expiration Date" := WorkDate() + 365;
        recReservationEntry.Insert();

        //Clear(codItemJnlPost);
        //codItemJnlPost.Run(recItemJournalLine);
    end;

    procedure GetLastNo(): Integer
    var
        recReservationEntry: Record "Reservation Entry";
        intLastEntryNo: Integer;
    begin
        recReservationEntry.Reset();
        if recReservationEntry.FindLast() then
            exit(recReservationEntry."Entry No." + 1);
        exit(1);
    end;

    var
        myInt: Integer;
}