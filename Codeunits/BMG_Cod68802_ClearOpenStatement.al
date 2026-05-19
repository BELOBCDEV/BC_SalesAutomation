codeunit 68802 BMGClearOpenStatement
{
    trigger OnRun()
    var
        recOpenStatement: Record "LSC Statement";
        recOpenStatementLine: Record "LSC Statement Line";
        codStatementPost: Codeunit "BMG LSC Statement-Post";
        codStatementCalculate: Codeunit "BMG LSC Statement-Calculate";
        bolDiffFound: Boolean;

    begin
        //if BatchPostingStatus <> '' then
        //   BatchPostingQueue.EditOpenStatement(Rec);

        recOpenStatement.Reset();
        IF recOpenStatement.FindFirst() then
            repeat
                recOpenStatementLine.Reset();
                recOpenStatementLine.SetRange("Statement No.", recOpenStatement."No.");

                bolDiffFound := false;
                if recOpenStatementLine.FindSet() then
                    repeat
                        if recOpenStatementLine."Difference Amount" <> 0 then
                            bolDiffFound := true;
                    until (recOpenStatementLine.Next() = 0) or (bolDiffFound <> false);

                if bolDiffFound then begin
                    if recOpenStatement.Status > recOpenStatement.Status::" " then begin
                        recOpenStatement.Status := recOpenStatement.Status::" ";
                        recOpenStatement.Modify();
                        codStatementPost.RunItemPosting(recOpenStatement, true);
                    end;
                    recOpenStatement.Get(recOpenStatement."Store No.", recOpenStatement."No.");
                    codStatementCalculate.SetTransactionsFree(recOpenStatement);
                    recOpenStatement.Recalculate := false;
                    recOpenStatement.Modify();

                    Clear(codStatementPost);
                    Clear(codStatementCalculate);

                end;
            until recOpenStatement.Next() = 0;


    end;

    var
        myInt: Integer;
}