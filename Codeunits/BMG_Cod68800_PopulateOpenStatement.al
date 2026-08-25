codeunit 68800 BMGPopulateOpenStatement
{
    trigger OnRun()
    var
        recOpenStatement: Record "LSC Statement";
        recOpenStatement2: Record "LSC Statement";
        recOpenStatementLine: Record "LSC Statement Line";
        recNoSeriesLine: Record "No. Series Line";
        recStore: Record "LSC Store";
        recTransHeader: Record "LSC Transaction Header";
        codNoSeriesMgt: Codeunit "No. Series";
        codStatementCalculate: Codeunit "LSC Statement-Calculate";
        codStatementCalculate2: Codeunit "BMG LSC Statement-Calculate";
        intCtr: Integer;
        codStore: code[10];
        codStatementNo: Code[20];
        codNoSeries: Code[10];
    begin
        //skip deletion of previous workdate
        /*
        recOpenStatement.Reset();
        recOpenStatement.SetFilter("Posted Date", '<>%1', WorkDate());

        if recOpenStatement.FindSet() then
            repeat
                recOpenStatementLine.Reset();
                recOpenStatementLine.SetRange("Statement No.", recOpenStatement."No.");

                if recOpenStatementLine.FindSet() then
                    recOpenStatementLine.DeleteAll();

                recOpenStatement.Delete();
            until recOpenStatement.Next() = 0;
        //recOpenStatement.DeleteAll();
        */

        recStore.Reset();
        recStore.SetRange("Include in Sales Automation", true);

        if recStore.FindFirst() then
            repeat
                codStore := recStore."No.";
                codNoSeries := recStore."Statement No. Series";

                recOpenStatement2.Reset();
                recOpenStatement2.SetRange("Store No.", codStore);
                recOpenStatement2.SetRange("Posting Date", WorkDate());

                if not recOpenStatement2.FindFirst() then begin
                    recTransHeader.Reset();
                    recTransHeader.SetRange("Store No.", codStore);
                    recTransHeader.SetRange(Date, WorkDate());
                    //recTransHeader.SetRange("Transaction Type", recTransHeader."Transaction Type"::"Tender Decl.");

                    if recTransHeader.FindFirst() then begin
                        recOpenStatement.Init();
                        recOpenStatement."Store No." := codStore;
                        codStatementNo := codNoSeriesMgt.GetNextNo(codNoSeries, WorkDate(), false);
                        recOpenStatement.Validate("No.", codStatementNo);
                        recOpenStatement.Validate("Posting Date", WorkDate());
                        recOpenStatement.Validate("VAT Reporting Date", WorkDate());
                        recOpenStatement.Validate("Trans. Starting Date", WorkDate());
                        recOpenStatement.Validate("Trans. Ending Date", WorkDate());
                        recOpenStatement."No. Series" := codNoSeries;
                        recOpenStatement."Posting No. Series" := codNoSeries;
                        recOpenStatement."No. Series." := codNoSeries;
                        recOpenStatement."Posting Nos." := codNoSeries;
                        If recOpenStatement.Insert() then;
                        codStatementCalculate2.Run(recOpenStatement);
                        Clear(codStatementCalculate2);
                    end;
                end else begin
                    recOpenStatementLine.Reset();
                    recOpenStatementLine.SetRange("Statement No.", recOpenStatement2."No.");
                    if NOT recOpenStatementLine.FindFirst() then begin
                        recTransHeader.Reset();
                        recTransHeader.SetRange("Store No.", codStore);
                        recTransHeader.SetRange(Date, WorkDate());
                        //recTransHeader.SetRange("Transaction Type", recTransHeader."Transaction Type"::"Tender Decl.");

                        if recTransHeader.FindFirst() then begin
                            codStatementCalculate2.Run(recOpenStatement);
                            Clear(codStatementCalculate2);
                        end;
                    end;
                end;

            until recStore.Next() = 0;

    end;




    var
        myInt: Integer;
}