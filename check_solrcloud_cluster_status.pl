#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-06-07 18:29:01 +0100 (Sat, 07 Jun 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Solr / SolrCloud cluster status via Solr Collections API

Checks:

For a given SolrCloud Collection or all collections found if --collection is not specified:

1. Checks there is at least one collection found
2. Checks each shard of the collection is 'active'
3. Checks each shard of the collection has at least one active replica
4. Checks each shard for any down backup replicas (can be optionally disabled)
5. Optionally shows replication settings per collection
6. Returns time since last cluster state change in both human form and perfdata secs for graphing

See also adjacent plugin check_solrcloud_cluster_status_zookeeper.pl which does the same as this check but goes via ZooKeeper which is tecnically the more correct thing to do since if the supplied SolrCloud node is down you will only get a 'connect refused' type feedback and not the extend of the outage in the cluster.

Tested on SolrCloud 4.x";

our $VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::Solr;

$ua->agent("Hari Sekhon $progname $main::VERSION");

%options = (
    %solroptions,
    %solroptions_collection,
    %solroptions_context,
    "no-warn-replicas" => [ \$no_warn_replicas, "Do not warn on down backup replicas (only check for shards being active and having at least one active replica)" ],
    "show-settings"    => [ \$show_settings,    "Show collection shard/replication settings" ],
);
splice @usage_order, 6, 0, qw/collection no-warn-replicas show-settings list-collections http-context/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
$http_context = validate_solr_context($http_context);
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

list_solr_collections();

$json = curl_solr "$solr_admin/collections?action=CLUSTERSTATUS";
# This makes it the same base as in ZooKeeper so reuses the parsing code from HariSekhon::Solr
$json = get_field("cluster.collections");

unless(scalar keys %$json){
    quit "CRITICAL", "no collections found in cluster state in zookeeper";
}

if($list_collections){
    print "Solr Collections:\n\n";
    foreach(sort keys %$json){
        print "$_\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

check_collections();

msg_shard_status();
$msg .= sprintf(', query time %dms, QTime %dms | query_time=%dms', $query_time, $query_qtime, $query_time);
msg_perf_thresholds();
$msg .= sprintf(' query_QTime=%dms', $query_qtime);

quit $status, $msg;
