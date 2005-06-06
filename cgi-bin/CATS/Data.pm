package CATS::Data;
use strict;
use warnings;

use CATS::Misc qw(:all);

BEGIN
{
    use Exporter;
    our @ISA = qw(Exporter);

    our @EXPORT = qw(
        get_registered_contestant
        enforce_request_state
        get_sources_info
        insert_ooc_user
        is_jury_in_contest
        get_judge_name
    );

    our %EXPORT_TAGS = (all => [ @EXPORT ]);
}


# �������� ���������� �� ��������� �������.
# ���������: fields, contest_id, account_id.
sub get_registered_contestant
{
    my %p = @_;
    $p{fields} ||= 1;
    $p{account_id} ||= $uid or return;
    $p{contest_id} or die;
    
    $dbh->selectrow_array(qq~
        SELECT $p{fields} FROM contest_accounts WHERE contest_id = ? AND account_id = ?~, {},
        $p{contest_id}, $p{account_id});
}


sub is_jury_in_contest
{
    my %p = @_;
    # �����������: ���� ������ � ������� �������, ������� ��� ��������� ��������.
    if (defined $cid && $p{contest_id} == $cid)
    {
        return $is_jury;
    }
    get_registered_contestant(fields => 'is_jury', @_);
}


# ������� ��������� ��������� ������� ���������. ����� ����� ��������� ��� ���������� ������������.
# ���������: request_id, state, failed_test.
sub enforce_request_state
{
    my %p = @_;
    defined $p{state} or return;
    $dbh->do(qq~
        UPDATE reqs
            SET failed_test = ?, state = ?,
                received = 0, result_time = CATS_SYSDATE(), judge_id = NULL 
            WHERE id = ?~, {},
        $p{failed_test}, $p{state}, $p{request_id}
    ) or return;
    $dbh->do(qq~DELETE FROM log_dumps WHERE req_id = ?~, {}, $p{request_id})
        or return;
    $dbh->commit;
    return 1;
}


# �������� ���������� �� �������� ������ ����� ��� ���������� �������.
# ���������: request_id.
sub get_sources_info
{
    my %p = @_;
    
    defined $p{request_id} or return;
    
    my $req_id_list;
    if (ref $p{request_id} eq 'ARRAY')
    {
        my @req_ids = grep defined $_ && $_ > 0, @{$p{request_id}}
            or return;

        $req_id_list = join ',', map sprintf('%d', $_), @req_ids;
    }
    else
    {
        $req_id_list = $p{request_id};
    }
    
    $req_id_list or return;
    
    my $src = $p{get_source} ? ' S.src,' : '';

    my $result = $dbh->selectall_arrayref(qq~
        SELECT
            S.req_id,$src S.fname AS file_name,
            R.account_id, R.contest_id, R.problem_id, R.judge_id,
            R.state, R.failed_test,
            CATS_DATE(R.submit_time) AS submit_time,
            CATS_DATE(R.test_time) AS test_time,
            CATS_DATE(R.result_time) AS result_time,
            DE.description AS de_name,
            A.team_name,
            P.title AS problem_name,
            C.title AS contest_name
        FROM sources S
            INNER JOIN reqs R ON R.id = S.req_id
            INNER JOIN default_de DE ON DE.id = S.de_id
            INNER JOIN accounts A ON A.id = R.account_id
            INNER JOIN problems P ON P.id = R.problem_id
            INNER JOIN contests C ON C.id = R.contest_id
        WHERE req_id IN ($req_id_list)~, { Slice => {} }
    ) or return;
    
    for my $r (@$result)
    {
        # ������ ������ �� ������� ������ � ��������� ���������.
        ($r->{"${_}_short"} = $r->{$_}) =~ s/^(.*)\s+(\d\d:\d\d)\s*$/$2/
            for qw(test_time result_time);
        $r = { %$r, state_to_display($r->{state}) };
    }

    return ref $p{request_id} ? $result : $result->[0];
}


sub get_judge_name
{
    my ($judge_id) = @_
        or return;
    my ($name) = $dbh->selectrow_array(qq~SELECT nick FROM judges WHERE id = ?~, {},
        $judge_id);
    return $name;
}


sub insert_ooc_user
{
    my %p = @_;
    $p{contest_id} ||= $cid or return;
    $dbh->do(qq~
        INSERT INTO contest_accounts (
            id, contest_id, account_id, is_jury, is_pop, is_hidden, is_ooc, is_remote,
            is_virtual, diff_time
        ) VALUES(?,?,?,?,?,?,?,?,?,?)~, {},
        new_id, $p{contest_id}, $p{account_id}, 0, 0, 0, 1, $p{is_remote} || 0,
        0, 0
    );
}


1;