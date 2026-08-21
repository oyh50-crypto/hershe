{#
    Simplified version of GA4's default channel grouping logic.
    Refine the medium/source keywords below to match this business's actual
    UTM conventions before relying on it for reporting.
#}
{% macro default_channel_grouping(source_col, medium_col, campaign_col) -%}
    case
        when {{ medium_col }} is null and {{ source_col }} is null then 'Direct'
        when {{ medium_col }} in ('cpc', 'ppc', 'paidsearch') then 'Paid Search'
        when {{ medium_col }} = 'organic' then 'Organic Search'
        when {{ medium_col }} in ('display', 'cpm', 'banner') then 'Display'
        when {{ medium_col }} in ('social', 'social-network', 'social-media', 'sm', 'paid_social')
            and {{ campaign_col }} is not null then 'Paid Social'
        when {{ medium_col }} in ('social', 'social-network', 'social-media', 'sm') then 'Organic Social'
        when {{ medium_col }} = 'email' then 'Email'
        when {{ medium_col }} = 'affiliate' then 'Affiliate'
        when {{ medium_col }} = 'referral' then 'Referral'
        else 'Other'
    end
{%- endmacro %}
