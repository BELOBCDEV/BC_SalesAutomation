pageextension 68800 BMGOpenStatementListExt extends "LSC Open Statement List"
{
    layout
    {
        // Add changes to page layout here
        addafter("Posting Date")
        {
            field("With Difference Amt"; bolWithDiff)
            {
                ApplicationArea = All;
            }
            field("With Error"; bolWithError)
            {
                ApplicationArea = All;
            }
        }
        addafter("No.")
        {
            field(StoreName; txtStoreName)
            {
                ApplicationArea = All;
            }
        }
    }

    actions
    {
        // Add changes to page actions here
        addafter("&Statement")
        {
            action(CreateStoresStatement)
            {
                Caption = 'Create Stores Statement';
                Image = Create;
                ApplicationArea = All;

                trigger OnAction()
                var
                    codPopulateOpenStatement: Codeunit BMGPopulateOpenStatement;
                begin
                    Clear(codPopulateOpenStatement);
                    codPopulateOpenStatement.Run();
                end;
            }
            action(ClearStoresStatement)
            {
                Caption = 'Clear Stores Statement';
                Image = ClearLog;
                ApplicationArea = All;

                trigger OnAction()
                var
                    codClearOpenStatement: Codeunit BMGClearOpenStatement;
                begin
                    Clear(codClearOpenStatement);
                    codClearOpenStatement.Run();
                end;
            }
            action(PostStoresStatement)
            {
                Caption = 'Post Stores Statement';
                Image = PostBatch;
                ApplicationArea = All;

                trigger OnAction()
                var
                    recStore: Record "LSC Store";
                    recOpenStatement: Record "LSC Statement";
                    recOpenStatementLine: Record "LSC Statement Line";
                    recLSCTransStatus: Record "LSC Transaction Status";
                    recItem: Record Item temporary;
                    codPostOpenStatement: Codeunit "BMG LSC Statement-Post";
                    BatchPostingStatus: Text[30];
                    BatchPosting: Codeunit "LSC Batch Posting";
                    bolErrorFound: Boolean;
                begin

                    recItem.DeleteAll();

                    recOpenStatement.Reset();
                    recOpenStatement.SetRange("Posting Date", WorkDate());

                    if recOpenStatement.FindFirst() then
                        repeat
                            recLSCTransStatus.Reset();
                            recLSCTransStatus.SetRange("Statement No.", recOpenStatement."No.");

                            if recLSCTransStatus.FindFirst() then
                                repeat
                                    bolErrorFound := false;
                                    if recLSCTransStatus."No. of Blank UOM Item" <> 0 then
                                        bolErrorFound := true;
                                    if recLSCTransStatus."Serial/Lot No. Not Valid" <> 0 then
                                        bolErrorFound := true;
                                    if recLSCTransStatus."Items/Barc. Not on File" <> 0 then
                                        bolErrorFound := true;
                                    if recLSCTransStatus."Blocked Customer" = true then
                                        bolErrorFound := true;
                                    if recLSCTransStatus."Items Blocked" <> 0 then
                                        bolErrorFound := true;
                                until (recLSCTransStatus.Next() = 0) OR (bolErrorFound = true);

                            recOpenStatementLine.Reset();
                            recOpenStatementLine.SetRange("Statement No.", recOpenStatement."No.");
                            recOpenStatementLine.SetFilter("Difference Amount", '<>%1', 0);

                            if recOpenStatementLine.FindFirst() then
                                bolErrorFound := true;

                            If not bolErrorFound then begin
                                recItem.Init();
                                recItem."No." := recOpenStatement."No.";
                                if recItem.Insert() then;
                                //Message('Statement No. %1 has been included for posting', recItem."No.");
                            end;

                        until recOpenStatement.Next() = 0;

                    recItem.Reset();
                    if recItem.FindFirst() then
                        repeat
                            //Message('Posting Statement No. %1', recItem."No.");
                            recOpenStatement.Reset();
                            recOpenStatement.SetRange("No.", recItem."No.");

                            if recOpenStatement.FindFirst() then begin
                                codPostOpenStatement.PostStatement(recOpenStatement, recStore, BatchPostingStatus, BatchPosting);
                                Clear(codPostOpenStatement);
                            end;

                        until recItem.Next() = 0;

                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        recOpenStatementLine: Record "LSC Statement Line";
        recLSCTransStatus: Record "LSC Transaction Status";
    begin
        bolWithDiff := false;
        bolWithError := false;

        recOpenStatementLine.Reset();
        recOpenStatementLine.SetRange("Statement No.", Rec."No.");
        recOpenStatementLine.SetFilter("Difference Amount", '<>%1', 0);

        if recOpenStatementLine.FindFirst() then
            bolWithDiff := true;

        recLSCTransStatus.Reset();
        recLSCTransStatus.SetRange("Statement No.", Rec."No.");

        if recLSCTransStatus.FindFirst() then
            repeat
                if recLSCTransStatus."Items Blocked" > 0 then
                    bolWithError := true;
                if recLSCTransStatus."Serial/Lot No. Not Valid" > 0 then
                    bolWithError := true;
                if recLSCTransStatus."Blocked Customer" = true then
                    bolWithError := true;
                if recLSCTransStatus."No. of Blank UOM Item" > 0 then
                    bolWithError := true;
                if recLSCTransStatus."Items/Barc. Not on File" > 0 then
                    bolWithError := true;

            until (recLSCTransStatus.Next() = 0) or (bolWithError = true);


        recStore.Reset();
        recStore.SetRange("No.", Rec."Store No.");

        if recStore.FindFirst() then
            txtStoreName := recStore.Name;
        CurrPage.Update(false);
    end;

    var
        recStore: Record "LSC Store";
        txtStoreName: Text[100];
        bolWithDiff: Boolean;
        bolWithError: Boolean;

}