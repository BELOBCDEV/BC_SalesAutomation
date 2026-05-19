codeunit 68804 BMGPOSStatementUtility
{
    trigger OnRun()
    var
        recOpenStatement: Record "LSC Statement";
    begin
        recOpenStatement.Reset();

        if recOpenStatement.FindFirst() then
            repeat

                case recOpenStatement."Store No." of
                    'B001':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B1';
                            recOpenStatement."Posting Nos." := 'R-STMT-B1';
                            recOpenStatement."No. Series" := 'R-STMT-B1';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B1';
                            //recOpenStatement.Modify();
                        end;
                    'B002':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B2';
                            recOpenStatement."Posting Nos." := 'R-STMT-B2';
                            recOpenStatement."No. Series" := 'R-STMT-B2';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B2';
                            //recOpenStatement.Modify();
                        end;
                    'B003':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B3';
                            recOpenStatement."Posting Nos." := 'R-STMT-B3';
                            recOpenStatement."No. Series" := 'R-STMT-B3';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B3';
                            //recOpenStatement.Modify();
                        end;
                    'B004':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B4';
                            recOpenStatement."Posting Nos." := 'R-STMT-B4';
                            recOpenStatement."No. Series" := 'R-STMT-B4';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B4';
                            //recOpenStatement.Modify();
                        end;
                    'B006':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B6';
                            recOpenStatement."Posting Nos." := 'R-STMT-B6';
                            recOpenStatement."No. Series" := 'R-STMT-B6';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B6';
                            //recOpenStatement.Modify();
                        end;
                    'B007':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B7';
                            recOpenStatement."Posting Nos." := 'R-STMT-B7';
                            recOpenStatement."No. Series" := 'R-STMT-B7';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B7';
                            //recOpenStatement.Modify();
                        end;
                    'B008':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B8';
                            recOpenStatement."Posting Nos." := 'R-STMT-B8';
                            recOpenStatement."No. Series" := 'R-STMT-B8';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B8';
                            //recOpenStatement.Modify();
                        end;
                    'B009':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B9';
                            recOpenStatement."Posting Nos." := 'R-STMT-B9';
                            recOpenStatement."No. Series" := 'R-STMT-B9';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B9';
                            //recOpenStatement.Modify();
                        end;
                    'B010':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B10';
                            recOpenStatement."Posting Nos." := 'R-STMT-B10';
                            recOpenStatement."No. Series" := 'R-STMT-B10';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B10';
                            //recOpenStatement.Modify();
                        end;
                    'B011':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B11';
                            recOpenStatement."Posting Nos." := 'R-STMT-B11';
                            recOpenStatement."No. Series" := 'R-STMT-B11';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B11';
                            //recOpenStatement.Modify();
                        end;
                    'B012':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B12';
                            recOpenStatement."Posting Nos." := 'R-STMT-B12';
                            recOpenStatement."No. Series" := 'R-STMT-B12';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B12';
                            //recOpenStatement.Modify();
                        end;
                    'B013':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B13';
                            recOpenStatement."Posting Nos." := 'R-STMT-B13';
                            recOpenStatement."No. Series" := 'R-STMT-B13';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B13';
                            //recOpenStatement.Modify();
                        end;
                    'B014':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B14';
                            recOpenStatement."Posting Nos." := 'R-STMT-B14';
                            recOpenStatement."No. Series" := 'R-STMT-B14';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B14';
                            //recOpenStatement.Modify();
                        end;
                    'B015':
                        begin
                            recOpenStatement."No. Series." := 'R-STMT-B15';
                            recOpenStatement."Posting Nos." := 'R-STMT-B15';
                            recOpenStatement."No. Series" := 'R-STMT-B15';
                            recOpenStatement."Posting No. Series" := 'R-STMT-B15';

                        end;

                end;
                recOpenStatement.Modify();

            until recOpenStatement.Next() = 0;

    end;

    var
        myInt: Integer;
}