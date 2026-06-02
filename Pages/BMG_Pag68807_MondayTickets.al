page 68807 BMGMondayTickets
{
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Administration;
    SourceTable = BMGMondayTickets;
    Caption = 'Monday.com Ticket';
    DataCaptionFields = "BMG Subject";


    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';

                field("Entry No."; Rec."Entry No.")
                {
                    ApplicationArea = All;
                    Editable = false;
                    Visible = false;
                }
                field("BMG Subject"; Rec."BMG Subject")
                {
                    ApplicationArea = All;
                    Caption = 'Subject';
                    Enabled = Rec."BMG Monday Item ID" = '';
                }
                field("Type of Request"; Rec."Type of Request")
                {
                    ApplicationArea = All;
                    Enabled = Rec."BMG Monday Item ID" = '';
                }
                field("BMG Priority"; Rec."BMG Priority")
                {
                    ApplicationArea = All;
                    Caption = 'Priority';
                    Enabled = Rec."BMG Monday Item ID" = '';
                }
                field("BMG Location"; Rec."BMG Location")
                {
                    ApplicationArea = All;
                    Caption = 'Location';
                    Enabled = Rec."BMG Monday Item ID" = '';
                }
                field("BMG Category"; Rec."BMG Category")
                {
                    ApplicationArea = All;
                    Visible = false;
                }
                field("BMG Ticket ID"; Rec."BMG Ticket ID")
                {
                    ApplicationArea = All;
                    Caption = 'ICT Ticket Number';
                    Editable = false;
                }
                field("BMG Status"; Rec."BMG Status")
                {
                    ApplicationArea = All;
                    Caption = 'Status';
                    Editable = false;
                    StyleExpr = StatusStyle;
                }
                field("Date Created"; Rec.SystemCreatedAt)
                {
                    ApplicationArea = All;
                    Caption = 'Date Created';
                    Editable = false;
                }
                field("Date Submitted"; Rec."Date Submitted")
                {
                    ApplicationArea = All;
                    Caption = 'Date Submitted';
                    Editable = false;
                }
            }
            group(Requester)
            {
                Caption = 'Requester';

                field("BMG Name"; Rec."BMG Name")
                {
                    ApplicationArea = All;
                    Editable = false;
                    Caption = 'Requestor Name';
                    Enabled = Rec."BMG Monday Item ID" = '';
                }
                field("BMG Assignee"; Rec."BMG Assignee")
                {
                    ApplicationArea = All;
                    Caption = 'Assignee';
                    Visible = false;
                }
                field("BMG Requestor Email"; Rec."BMG Requestor Email")
                {
                    ApplicationArea = All;
                    Editable = true;
                    Caption = 'Requestor Email';
                    Enabled = Rec."BMG Monday Item ID" = '';
                }
                field("BMG Assignee User"; Rec."BMG Assignee User")
                {
                    ApplicationArea = All;
                    Caption = 'Assignee';
                    Enabled = Rec."BMG Monday Item ID" = '';
                }
            }
            group(Details)
            {
                Caption = 'Details';

                field("BMG Comment"; Rec."BMG Comment")
                {
                    ApplicationArea = All;
                    MultiLine = true;
                    Caption = 'Comment';
                    Enabled = Rec."BMG Monday Item ID" = '';
                }
                field("BMG Description"; Rec."BMG Description")
                {
                    ApplicationArea = All;
                    MultiLine = true;
                    Caption = 'Description';
                    Enabled = Rec."BMG Monday Item ID" = '';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(SubmitToMonday)
            {
                ApplicationArea = All;
                Caption = 'Submit to Monday.com';
                Image = SendTo;

                trigger OnAction()
                var
                    MondayMgt: Codeunit BMGMondayDotComMgt;
                    recSalesSetup: Record "Sales & Receivables Setup";
                begin

                    recSalesSetup.Get();

                    Clear(MondayMgt);
                    MondayMgt.SetApiToken(recSalesSetup."API Key 2");
                    MondayMgt.ComposeTicket(
                        Rec."BMG Subject",
                        Rec."BMG Comment",
                        Format(Rec."Type of Request"),
                        Format(Rec."BMG Priority"),
                        Format(Rec."BMG Location"),
                        Rec."BMG Description",
                        Rec, 1);
                    CurrPage.Update(false);
                end;
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
        }
        area(Promoted)
        {
            actionref(SubmitToMonday_Promoted; SubmitToMonday) { }
            actionref(RefreshStatus_Promoted; RefreshStatus) { }
            actionref(AttachFile_Promoted; AttachFile) { }
        }
    }

    var
        StatusStyle: Text;

    trigger OnAfterGetRecord()
    begin
        case Rec."BMG Status" of
            'Done':
                StatusStyle := 'Favorable';
            'Stuck':
                StatusStyle := 'Unfavorable';
            'Working on it':
                StatusStyle := 'Ambiguous';
            else
                StatusStyle := 'None';
        end;
    end;
}
