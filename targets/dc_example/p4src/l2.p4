/*
Copyright 2013-present Barefoot Networks, Inc. 

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

header_type l2_metadata_t {
    fields {
        /* Ingress Metadata */
        ifindex : IFINDEX_BIT_WIDTH;           /* input interface index - MSB bit lag*/
        lif : 16;                              /* logical interface */
        lkp_pkt_type : 3;
        lkp_mac_sa : 48;
        lkp_mac_da : 48;
        lkp_mac_type : 16;

        if_label : 16;                         /* if label for acls */
        bd_label : 16;                         /* bd label for acls */

        l2_src_miss : 1;                       /* l2 source miss */
        l2_src_move : IFINDEX_BIT_WIDTH;       /* l2 source interface mis-match */
        l2_redirect : 1;                       /* l2 redirect action */
        learn_mac : 48;                        /* mac learn data */
        l2_nexthop : 16;                       /* next hop from l2 */
        l2_ecmp : 10;                          /* ecmp index from l2 */
        bd : BD_BIT_WIDTH;                     /* inner BD */
        egress_bd : BD_BIT_WIDTH;              /* egress BD */
        stp_group: 10;                         /* spanning tree group id */
        stp_state : 3;                         /* spanning tree port state */
        stp_enabled: 1;                        /* spanning tree is enabled */
        egress_ifindex : IFINDEX_BIT_WIDTH;    /* egress interface index */

        /* Egress Metadata */
        egress_smac_idx : 9;                   /* index into source mac table */
        egress_mac_da : 48;                    /* final mac da */
    }
}

metadata l2_metadata_t l2_metadata;

action set_valid_outer_unicast_packet() {
    modify_field(l2_metadata.lkp_pkt_type, L2_UNICAST);
    modify_field(l2_metadata.lkp_mac_sa, ethernet.srcAddr);
    modify_field(l2_metadata.lkp_mac_da, ethernet.dstAddr);
    modify_field(l2_metadata.lkp_mac_type, ethernet.etherType);
}

action set_valid_outer_multicast_packet() {
    modify_field(l2_metadata.lkp_pkt_type, L2_MULTICAST);
    modify_field(l2_metadata.lkp_mac_sa, ethernet.srcAddr);
    modify_field(l2_metadata.lkp_mac_da, ethernet.dstAddr);
    modify_field(l2_metadata.lkp_mac_type, ethernet.etherType);
}

action set_valid_outer_broadcast_packet() {
    modify_field(l2_metadata.lkp_pkt_type, L2_BROADCAST);
    modify_field(l2_metadata.lkp_mac_sa, ethernet.srcAddr);
    modify_field(l2_metadata.lkp_mac_da, ethernet.dstAddr);
    modify_field(l2_metadata.lkp_mac_type, ethernet.etherType);
}

table validate_outer_ethernet {
    reads {
        ethernet.dstAddr : ternary;
    }
    actions {
        set_valid_outer_unicast_packet;
        set_valid_outer_multicast_packet;
        set_valid_outer_broadcast_packet;
    }
    size : VALIDATE_PACKET_TABLE_SIZE;
} 

control validate_outer_ethernet_header {
    /* validate the ethernet header */
    apply(validate_outer_ethernet);
}

action set_ifindex(ifindex, if_label) {
    modify_field(l2_metadata.ifindex, ifindex);
    modify_field(l2_metadata.if_label, if_label);
}

table port_mapping {
    reads {
        standard_metadata.ingress_port : exact;
    }
    actions {
        set_ifindex;
    }
    size : PORTMAP_TABLE_SIZE;
}

table port_vlan_mapping {
    reads {
        l2_metadata.ifindex : exact;
        vlan_tag_[0] : valid;
        vlan_tag_[0].vid : exact;
        vlan_tag_[1] : valid;
        vlan_tag_[1].vid : exact;
    }

    action_profile: outer_bd_action_profile;
    size : PORT_VLAN_TABLE_SIZE;
}

control port_vlan_mapping_lookup {
    /* input mapping - derive an ifindex */
    apply(port_mapping);

    /* derive lif, bd */
    apply(port_vlan_mapping);
}

action set_stp_state(stp_state) {
    modify_field(l2_metadata.stp_state, stp_state);
}

table spanning_tree {
    reads {
        l2_metadata.ifindex : exact;
        l2_metadata.stp_group: exact;
    }
    actions {
        set_stp_state;
    }
    size : SPANNING_TREE_TABLE_SIZE;
}

control spanning_tree_lookup {
    if (l2_metadata.stp_group != STP_GROUP_NONE) {
        apply(spanning_tree);
    }
}

action set_bd(outer_vlan_bd, vrf, rmac_group, 
        ipv4_unicast_enabled, 
        stp_group) {
    modify_field(l3_metadata.vrf, vrf);
    modify_field(l3_metadata.ipv4_unicast_enabled, ipv4_unicast_enabled);
    modify_field(tunnel_metadata.outer_rmac_group, rmac_group);
    modify_field(l2_metadata.bd, outer_vlan_bd);
    modify_field(l2_metadata.stp_group, stp_group);
}

/*
* outer_bd is used to extract the tunnel termination 
*   actions
*/
action_profile outer_bd_action_profile {
    actions {
        set_bd;
    }
    size : OUTER_BD_TABLE_SIZE;
}

action set_bd_info(vrf, rmac_group, 
        bd_label, uuc_mc_index, bcast_mc_index, umc_mc_index,
        ipv4_unicast_enabled, 
        igmp_snooping_enabled, stp_group) {
    modify_field(l3_metadata.vrf, vrf);
    modify_field(l3_metadata.ipv4_unicast_enabled, ipv4_unicast_enabled);
    modify_field(mcast_metadata.igmp_snooping_enabled, igmp_snooping_enabled);
    modify_field(l3_metadata.rmac_group, rmac_group);
    modify_field(mcast_metadata.uuc_mc_index, uuc_mc_index);
    modify_field(mcast_metadata.umc_mc_index, umc_mc_index);
    modify_field(mcast_metadata.bcast_mc_index, bcast_mc_index);
    modify_field(l2_metadata.bd_label, bd_label);
    modify_field(l2_metadata.stp_group, stp_group);
}

/*
* extract all the bridge domain parameters for non-tunneled
*   packets
*/
table bd {
    reads {
        l2_metadata.bd : exact;
    }
    actions {
        set_bd_info;
    }
    size : BD_TABLE_SIZE;
}

control bd_lookup {
    /* extract BD related parameters */
    apply(bd);
}

action set_l2_multicast() {
    modify_field(mcast_metadata.l2_multicast, TRUE);
}

action set_src_is_link_local() {
    modify_field(mcast_metadata.src_is_link_local, TRUE);
}

action set_malformed_packet() {
}

table validate_packet {
    reads {
        l2_metadata.lkp_mac_da : ternary;
        l3_metadata.lkp_ipv4_da : ternary;
    }
    actions {
        nop;
        set_l2_multicast;
        set_src_is_link_local;
        set_malformed_packet;
    }
    size : VALIDATE_PACKET_TABLE_SIZE;
}

action smac_miss() {
    modify_field(l2_metadata.l2_src_miss, TRUE);
}

action smac_hit(ifindex) {
    bit_xor(l2_metadata.l2_src_move, l2_metadata.ifindex, ifindex);
    add_to_field(l2_metadata.egress_bd, 0);
}

table smac {
    reads {
        l2_metadata.bd : exact;
        l2_metadata.lkp_mac_sa : exact;
    }
    actions {
        nop;
        smac_miss;
        smac_hit;
    }
    size : SMAC_TABLE_SIZE;
}

control smac_lookup_and_learn {
    /* validate packet */
    apply(validate_packet);

    /* l2 lookups */
    apply(smac);

    /* generate learn notify digest if permitted */
    apply(learn_notify);
}

action dmac_hit(ifindex) {
    modify_field(l2_metadata.egress_ifindex, ifindex);
    modify_field(l2_metadata.egress_bd, l2_metadata.bd);
}

action dmac_multicast_hit(mc_index) {
    modify_field(intrinsic_metadata.eg_mcast_group, mc_index);
    modify_field(l2_metadata.egress_bd, l2_metadata.bd);
}

action dmac_miss() {
    modify_field(intrinsic_metadata.eg_mcast_group, mcast_metadata.uuc_mc_index);
}

action dmac_redirect_nexthop(nexthop_index) {
    modify_field(l2_metadata.l2_redirect, TRUE);
    modify_field(l2_metadata.l2_nexthop, nexthop_index);
}

action dmac_redirect_ecmp(ecmp_index) {
    modify_field(l2_metadata.l2_redirect, TRUE);
    modify_field(l2_metadata.l2_ecmp, ecmp_index);
}

table dmac {
    reads {
        l2_metadata.bd : exact;
        l2_metadata.lkp_mac_da : exact;
    }
    actions {
        nop;
        dmac_hit;
        dmac_multicast_hit;
        dmac_miss;
        dmac_redirect_nexthop;
        dmac_redirect_ecmp;
    }
    size : DMAC_TABLE_SIZE;
    support_timeout: true;
}

control dmac_lookup {
    apply(dmac);
}

action set_rmac_hit_flag() {
    modify_field(l3_metadata.rmac_hit, TRUE);
}

field_list lag_hash_fields {
    l2_metadata.lkp_mac_sa;
    l2_metadata.lkp_mac_da;
    l2_metadata.lkp_mac_type;
    l3_metadata.lkp_ipv4_sa;
    l3_metadata.lkp_ipv4_da;
    l3_metadata.lkp_ip_proto;
    l3_metadata.lkp_l4_sport;
    l3_metadata.lkp_l4_dport;
}

field_list_calculation lag_hash {
    input {
        lag_hash_fields;
    }
    algorithm : crc16;
    output_width : LAG_BIT_WIDTH;
}

action_selector lag_selector {
    selection_key : lag_hash;
}

action set_lag_port(port) {
    modify_field(standard_metadata.egress_spec, port);
}

action_profile lag_action_profile {
    actions {
        nop;
        set_lag_port;
    }
    size : LAG_GROUP_TABLE_SIZE;
    selector : lag_selector;
}

table lag_group {
    reads {
        l2_metadata.egress_ifindex : exact;
    }
    action_profile: lag_action_profile;
    size : LAG_SELECT_TABLE_SIZE;
}

control lag_lookup {
    /* resolve final egress port for unicast traffic */
    apply(lag_group);
}

field_list mac_learn_digest {
    l2_metadata.bd;
    l2_metadata.lkp_mac_sa;
    l2_metadata.ifindex;
}

action generate_learn_notify() {
    generate_digest(MAC_LEARN_RECIEVER, mac_learn_digest);
}

table learn_notify {
    reads {
        l2_metadata.l2_src_miss : ternary;
        l2_metadata.l2_src_move : ternary;
        l2_metadata.stp_state : ternary;
    }
    actions {
        nop;
        generate_learn_notify;
    }
    size : LEARN_NOTIFY_TABLE_SIZE;
}

action rewrite_unicast_mac(smac) {
    modify_field(ethernet.srcAddr, smac);
    modify_field(ethernet.dstAddr, l2_metadata.egress_mac_da);
}

action rewrite_multicast_mac(smac) {
    modify_field(ethernet.srcAddr, smac);
    modify_field(ethernet.dstAddr, 0x01005E000000);
    modify_field(ethernet.dstAddr, ipv4.dstAddr, 0x7FFFFF);
    add_to_field(ipv4.ttl, -1);
}

table mac_rewrite {
    reads {
        l2_metadata.egress_smac_idx : exact;
        ipv4.dstAddr : ternary;
    }
    actions {
        nop;
        rewrite_unicast_mac;
        rewrite_multicast_mac;
    }
    size : SOURCE_MAC_TABLE_SIZE;
}

control mac_rewrite_lookup {
    /* rewrite source/destination mac if needed */
    if (l3_metadata.egress_routed == TRUE) {
        apply(mac_rewrite);
    }
}

action set_egress_packet_vlan_tagged(vlan_id) {
    add_header(vlan_tag_[0]);
    modify_field(vlan_tag_[0].vid, vlan_id);
}

action set_egress_packet_vlan_untagged() {
    remove_header(vlan_tag_[0]);
}

table egress_vlan_xlate {
    reads {
        standard_metadata.egress_port : exact;
        egress_metadata.bd : exact;
    }
    actions {
        nop;
        set_egress_packet_vlan_tagged;
        set_egress_packet_vlan_untagged;
    }
    size : EGRESS_VLAN_XLATE_TABLE_SIZE;
}

action egress_drop () {
    drop();
}

table egress_block {
    reads {
        standard_metadata.egress_port : exact;
        intrinsic_metadata.replication_id : exact;
    }
    actions {
        on_miss;
        egress_drop;
    }
    size : EGRESS_BLOCK_TABLE_SIZE;
}

control prune_and_xlate_lookup {
    apply(egress_block) {
	    on_miss {
        /* egress vlan translation */
            apply(egress_vlan_xlate);
        }
    }
}
