page 68808 BMGMondayTicketList
{
    Caption = 'BC Monday Ticket List';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Administration;
    SourceTable = BMGMondayTickets;
    CardPageId = BMGMondayTickets;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Entry No."; Rec."Entry No.")
                {
                    ApplicationArea = All;
                }
                field("BMG Subject"; Rec."BMG Subject")
                {
                    ApplicationArea = All;
                    Caption = 'Subject';
                }
                field("BMG Ticket ID"; Rec."BMG Ticket ID")
                {
                    ApplicationArea = All;
                    Caption = 'ICT Ticket Number';
                }
                field("BMG Comment"; Rec."BMG Comment")
                {
                    ApplicationArea = All;
                    Caption = 'Comment';
                }
                field("BMG Name"; Rec."BMG Name")
                {
                    ApplicationArea = All;
                    Caption = 'Requestor Name';
                }
                field("BMG Status"; Rec."BMG Status")
                {
                    ApplicationArea = All;
                    Caption = 'Status';
                    StyleExpr = StatusStyle;
                }
                field("Type of Request"; Rec."Type of Request")
                {
                    ApplicationArea = All;
                }
                field("BMG Priority"; Rec."BMG Priority")
                {
                    ApplicationArea = All;
                    Caption = 'Priority';
                }
                field("BMG Location"; Rec."BMG Location")
                {
                    ApplicationArea = All;
                    Caption = 'Location';
                }

                field("BMG Requestor Email"; Rec."BMG Requestor Email")
                {
                    ApplicationArea = All;
                    Caption = 'Requestor Email';
                }

                field("BMG Description"; Rec."BMG Description")
                {
                    ApplicationArea = All;
                    Caption = 'Description';
                }
                field("BMG Assignee User"; Rec."BMG Assignee User")
                {
                    ApplicationArea = All;
                    Caption = 'Assignee';
                }
                field("Date Created"; Rec.SystemCreatedAt)
                {
                    ApplicationArea = All;
                    Caption = 'Date Created';
                }
                field("Date Submitted"; Rec."Date Submitted")
                {
                    ApplicationArea = All;
                    Caption = 'Date Submitted';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(NewTicket)
            {
                ApplicationArea = All;
                Caption = 'New Ticket';
                Image = New;
                RunObject = page BMGMondayTickets;
                RunPageMode = Create;
            }

            action(RefreshStatus)
            {
                ApplicationArea = All;
                Caption = 'Refresh Status';
                Image = Refresh;
                Enabled = Rec."BMG Monday Item ID" <> '';

                trigger OnAction()
                var
                    MondayMgt: Codeunit BMGMondayDotComMgt;
                begin
                    Rec."BMG Status" := MondayMgt.GetTicketStatus(Rec."BMG Monday Item ID");
                    Rec."BMG Assignee" := MondayMgt.FetchAssignee(Rec."BMG Monday Item ID");
                    MondayMgt.UpdateAssigneeFields(Rec."BMG Assignee", Rec);
                    Rec."BMG Requestor Email" := MondayMgt.FetchRequestorEmail(Rec."BMG Monday Item ID");
                    Rec.Modify();
                    CurrPage.Update(false);
                end;
            }
            action(AttachFile)
            {
                ApplicationArea = All;
                Caption = 'Attach File';
                Image = Attach;
                Enabled = Rec."BMG Monday Item ID" <> '';

                trigger OnAction()
                var
                    MondayMgt: Codeunit BMGMondayDotComMgt;
                    FileStream: InStream;
                    FileName: Text;
                begin
                    if not UploadIntoStream('Select file to attach', '', 'All Files (*.*)|*.*', FileName, FileStream) then
                        exit;
                    MondayMgt.AddFileToTicket(Rec."BMG Monday Item ID", 'files', FileName, FileStream);
                    Message('File "%1" attached successfully.', FileName);
                end;
            }

            action(ShowBoard2Columns)
            {
                ApplicationArea = All;
                Caption = 'Show Board 2 Columns';
                Image = Info;

                trigger OnAction()
                var
                    MondayMgt: Codeunit BMGMondayDotComMgt;
                    recSalesSetup: Record "Sales & Receivables Setup";
                begin
                    recSalesSetup.Get();
                    MondayMgt.SetApiToken(recSalesSetup."API Key 2");
                    MondayMgt.ShowBoardColumns(recSalesSetup."Cross-Dept Request Board ID");
                end;
            }
        }
        area(Promoted)
        {
            actionref(NewTicket_Promoted; NewTicket) { }
            actionref(RefreshStatus_Promoted; RefreshStatus) { }
            actionref(AttachFile_Promoted; AttachFile) { }
        }
    }

    var
        StatusStyle: Text;

    trigger OnAfterGetRecord()
    begin
        case Rec."BMG Status" of
            'New':
                StatusStyle := 'Subordinate';
            'Working on it':
                StatusStyle := 'Ambiguous';
            'Waiting for Approval':
                StatusStyle := 'Attention';
            'Done':
                StatusStyle := 'Favorable';
            'Pending':
                StatusStyle := 'Strong';
            else
                StatusStyle := 'Standard';
        end;
    end;

    trigger OnOpenPage()
    var
        recMondayTicket: Record BMGMondayTickets;
    begin
        recMondayTicket.Reset();
        recMondayTicket.SetRange(SystemCreatedBy, UserSecurityId());
        CurrPage.SetTableView(recMondayTicket);
    end;
}
